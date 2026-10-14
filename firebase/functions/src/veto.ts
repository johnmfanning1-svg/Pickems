import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendToUser } from "./notifications";
import {
  alertCollapseId,
  gameContextSubtitle,
  gameDeepLink,
  leagueDisplayName,
  leagueThreadId,
  matchupFromGame,
  type MatchupInput,
} from "./pushAlert";
import { kickoffMillis } from "./pickLock";

/**
 * Selection veto (commissioner setting `rules.allowVeto`, off by default).
 *
 * Clients create `groups/{g}/weeks/{w}/nominations/{n}/vetoVotes/{uid}`. The
 * Firestore rules gate who may vote and when (member, not the selector, one
 * doc per uid, Selections open, before that game's kickoff). This trigger
 * recounts the votes in a transaction, re-checks the same window, and once the
 * threshold is met removes the Selection, records `weeks/{w}/vetoes/{espnEventId}`
 * and pushes every member.
 */

export const DEFAULT_VETO_VOTES_NEEDED = 2;

export interface VetoGroupData {
  name?: unknown;
  memberIds?: unknown;
  rules?: { allowVeto?: unknown; vetoVotesNeeded?: unknown } | null;
}

export interface VetoWeekData {
  status?: unknown;
  selectionDeadline?: unknown;
  weekNumber?: unknown;
}

export interface VetoNominationData {
  submittedBy?: unknown;
  submitterName?: unknown;
  espnEventId?: unknown;
  kickoff?: unknown;
  [key: string]: unknown;
}

function memberIdsOf(group: VetoGroupData | undefined): string[] {
  return Array.isArray(group?.memberIds)
    ? (group!.memberIds as unknown[]).filter((id): id is string => typeof id === "string" && id.length > 0)
    : [];
}

/**
 * Votes needed, clamped to 1…(league size − 1) because the selector cannot vote.
 * Missing or invalid settings fall back to 2.
 */
export function vetoThreshold(votesNeeded: unknown, memberCount: number): number {
  const eligible = Math.max(1, Math.floor(memberCount) - 1);
  const raw =
    typeof votesNeeded === "number" && Number.isFinite(votesNeeded)
      ? Math.floor(votesNeeded)
      : DEFAULT_VETO_VOTES_NEEDED;
  return Math.min(Math.max(1, raw), eligible);
}

export type VetoPlan =
  | { action: "remove"; threshold: number; voteCount: number }
  | { action: "wait"; threshold: number; voteCount: number }
  | { action: "ignore"; reason: string };

/** Same window the rules enforce, re-checked at count time. */
export function planVeto(input: {
  nowMs: number;
  group: VetoGroupData | undefined;
  week: VetoWeekData | undefined;
  nomination: VetoNominationData | undefined;
  /** Vote doc ids (voter uids) currently stored on the nomination. */
  voterIds: string[];
}): VetoPlan {
  const { group, week, nomination, nowMs } = input;
  if (!group || !week || !nomination) return { action: "ignore", reason: "missing_doc" };
  if (group.rules?.allowVeto !== true) return { action: "ignore", reason: "veto_off" };
  if (week.status !== "selection") return { action: "ignore", reason: "selections_closed" };
  const deadlineMs = kickoffMillis(week.selectionDeadline);
  if (deadlineMs != null && nowMs >= deadlineMs) return { action: "ignore", reason: "selection_deadline_passed" };
  const kickoffMs = kickoffMillis(nomination.kickoff);
  if (kickoffMs == null || nowMs >= kickoffMs) return { action: "ignore", reason: "kickoff_passed" };

  const members = new Set(memberIdsOf(group));
  const selector = typeof nomination.submittedBy === "string" ? nomination.submittedBy : "";
  // Only current members other than the selector count, once each.
  const voters = new Set(input.voterIds.filter((id) => id !== selector && members.has(id)));
  const threshold = vetoThreshold(group.rules?.vetoVotesNeeded, members.size);
  if (voters.size >= threshold) return { action: "remove", threshold, voteCount: voters.size };
  return { action: "wait", threshold, voteCount: voters.size };
}

export interface VetoPush {
  title: string;
  body: string;
  subtitle: string;
  data: Record<string, string>;
  threadId: string;
  collapseId: string;
}

/** Every alert names the game and the league and deep-links to that game in that league. */
export function buildVetoPush(input: {
  leagueName: unknown;
  groupId: string;
  weekId: string;
  gameId: string;
  matchup: MatchupInput;
  selectorName: string;
  isSelector: boolean;
}): VetoPush {
  const league = leagueDisplayName(input.leagueName);
  const game = `${input.matchup.away} @ ${input.matchup.home}`;
  const subtitle = gameContextSubtitle(league, { away: input.matchup.away, home: input.matchup.home });
  const title = input.isSelector ? "Your Selection was vetoed" : "Selection vetoed";
  const body = input.isSelector
    ? `${league} vetoed ${game}. Pick another game before Selections close.`
    : `${league} vetoed ${input.selectorName}'s pick of ${game}. They get to reselect.`;
  return {
    title,
    body,
    subtitle,
    threadId: leagueThreadId(input.groupId),
    collapseId: alertCollapseId(input.groupId, "veto", input.gameId),
    data: {
      groupId: input.groupId,
      weekId: input.weekId,
      gameId: input.gameId,
      deepLink: gameDeepLink(input.groupId, input.weekId, input.gameId),
    },
  };
}

export const onSelectionVetoVote = onDocumentCreated(
  "groups/{groupId}/weeks/{weekId}/nominations/{nominationId}/vetoVotes/{voterId}",
  async (event) => {
    const { groupId, weekId, nominationId } = event.params;
    const db = getFirestore();
    const groupRef = db.collection("groups").doc(groupId);
    const weekRef = groupRef.collection("weeks").doc(weekId);
    const nomRef = weekRef.collection("nominations").doc(nominationId);
    const votesRef = nomRef.collection("vetoVotes");

    const outcome = await db.runTransaction(async (tx) => {
      const [groupSnap, weekSnap, nomSnap, votesSnap] = await Promise.all([
        tx.get(groupRef),
        tx.get(weekRef),
        tx.get(nomRef),
        tx.get(votesRef),
      ]);
      const group = groupSnap.data() as VetoGroupData | undefined;
      const nomination = nomSnap.data() as VetoNominationData | undefined;
      const plan = planVeto({
        nowMs: Date.now(),
        group,
        week: weekSnap.data() as VetoWeekData | undefined,
        nomination,
        voterIds: votesSnap.docs.map((d) => d.id),
      });
      if (plan.action === "wait") {
        tx.update(nomRef, { vetoVoteCount: plan.voteCount, vetoVotesNeeded: plan.threshold });
        return { plan };
      }
      if (plan.action !== "remove" || !nomination || !group) return { plan };

      const espnEventId =
        typeof nomination.espnEventId === "string" && nomination.espnEventId ? nomination.espnEventId : nominationId;
      // Same cleanup as the app's Remove Selection: drop slate games for this event
      // and decrement nominationCount so the selector's slot is free again.
      const gamesSnap = await tx.get(weekRef.collection("games").where("espnEventId", "==", espnEventId));
      const gameRefs = new Map(gamesSnap.docs.map((d) => [d.ref.path, d.ref]));
      const byIdRef = weekRef.collection("games").doc(espnEventId);
      gameRefs.set(byIdRef.path, byIdRef);
      tx.set(weekRef.collection("vetoes").doc(espnEventId), {
        espnEventId,
        nominationId,
        submittedBy: nomination.submittedBy ?? null,
        submitterName: nomination.submitterName ?? null,
        homeTeamName: nomination.homeTeamName ?? null,
        homeTeamAbbreviation: nomination.homeTeamAbbreviation ?? null,
        awayTeamName: nomination.awayTeamName ?? null,
        awayTeamAbbreviation: nomination.awayTeamAbbreviation ?? null,
        kickoff: nomination.kickoff instanceof Timestamp ? nomination.kickoff : null,
        voteCount: plan.voteCount,
        votesNeeded: plan.threshold,
        vetoedAt: FieldValue.serverTimestamp(),
      });
      tx.delete(nomRef);
      for (const ref of gameRefs.values()) tx.delete(ref);
      tx.update(weekRef, { nominationCount: FieldValue.increment(-1) });
      return { plan, nomination, group, espnEventId, voteRefs: votesSnap.docs.map((d) => d.ref) };
    });

    if (outcome.plan.action !== "remove" || !outcome.nomination || !outcome.group) {
      logger.info("veto vote counted", { groupId, weekId, nominationId, plan: outcome.plan });
      return;
    }

    // Votes are anonymous and only meaningful on a live Selection.
    const batch = db.batch();
    for (const ref of outcome.voteRefs ?? []) batch.delete(ref);
    await batch.commit().catch((err) =>
      logger.warn("veto vote cleanup failed", { groupId, weekId, nominationId, error: String(err) })
    );

    const nomination = outcome.nomination;
    const selector = typeof nomination.submittedBy === "string" ? nomination.submittedBy : "";
    const selectorName =
      typeof nomination.submitterName === "string" && nomination.submitterName.trim()
        ? nomination.submitterName.trim()
        : "A member";
    const matchup = matchupFromGame(nomination as Parameters<typeof matchupFromGame>[0]);
    const members = memberIdsOf(outcome.group);
    await Promise.all(
      members.map((uid) => {
        const push = buildVetoPush({
          leagueName: outcome.group!.name,
          groupId,
          weekId,
          gameId: outcome.espnEventId!,
          matchup,
          selectorName,
          isSelector: uid === selector,
        });
        return sendToUser(
          uid,
          push.title,
          push.body,
          "selection_veto",
          push.data,
          undefined,
          {
            subtitle: push.subtitle,
            payloadType: "selection_veto",
            threadId: push.threadId,
            collapseId: push.collapseId,
          }
        ).catch(() => undefined);
      })
    );
    logger.info("selection vetoed", { groupId, weekId, nominationId, plan: outcome.plan });
  }
);
