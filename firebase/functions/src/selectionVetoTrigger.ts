import {
  FieldValue,
  getFirestore,
  type CollectionReference,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type QueryDocumentSnapshot,
  type Transaction,
} from "firebase-admin/firestore";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendToUser } from "./notifications";
import { buildSelectionVetoPush, leagueDisplayName, teamTag } from "./pushAlert";
import {
  deadlineMillis,
  memberIdList,
  nominationCountAfterRemoval,
  planSelectionVeto,
  selectionMatchupLabel,
  selectionVetoMessages,
  indexOfPendingVetoRecord,
  selectionVetoRecordId,
  slateGameIdsForEvent,
  vetoSettingsMayApply,
  type SelectionVetoPlan,
  type VetoGroupFields,
} from "./selectionVeto";

function db(): Firestore {
  return getFirestore();
}

interface VetoNotice {
  groupId: string;
  weekId: string;
  gameId: string;
  selectorId: string;
  memberIds: string[];
  gameLabel: string;
  leagueName: string;
  away: string;
  home: string;
  vetoId: string;
}

/**
 * A member's veto vote. Rules already rejected votes outside the Selection
 * window, from the selector, and while the feature is off. This recounts
 * eligible votes and, at the threshold, removes the Selection.
 */
export const onSelectionVetoVoteCreated = onDocumentCreated(
  "groups/{groupId}/weeks/{weekId}/nominations/{nominationId}/vetoVotes/{voterId}",
  async (event) => {
    const groupId = event.params.groupId;
    const weekId = event.params.weekId;
    const nominationId = event.params.nominationId;
    const voterId = event.params.voterId;
    if (!groupId || !weekId || !nominationId || !voterId) return;
    await evaluateSelectionVeto(db(), {
      groupId,
      weekId,
      nominationId,
      triggerVoterId: voterId,
    });
  }
);

/**
 * Turning veto on, lowering the votes required, or losing a member can make
 * votes already cast reach the threshold without anyone voting again.
 */
export const onGroupVetoSettingsUpdated = onDocumentUpdated(
  "groups/{groupId}",
  async (event) => {
    const before = event.data?.before.data() as VetoGroupFields | undefined;
    const after = event.data?.after.data() as VetoGroupFields | undefined;
    if (!before || !after) return;
    if (!vetoSettingsMayApply(before, after)) return;

    const groupId = event.params.groupId;
    const weeks = await db()
      .collection("groups")
      .doc(groupId)
      .collection("weeks")
      .where("status", "==", "selection")
      .get();

    for (const week of weeks.docs) {
      const nominations = await week.ref.collection("nominations").get();
      for (const nomination of nominations.docs) {
        await evaluateSelectionVeto(db(), {
          groupId,
          weekId: week.id,
          nominationId: nomination.id,
          triggerVoterId: null,
        });
      }
    }
  }
);

/**
 * Recount one Selection and apply the plan. Exported so the two triggers share
 * one transaction. Idempotent: a retry after the Selection is gone only
 * finishes an unsent notification.
 */
export async function evaluateSelectionVeto(
  firestore: Firestore,
  input: {
    groupId: string;
    weekId: string;
    nominationId: string;
    triggerVoterId: string | null;
  }
): Promise<void> {
  const { groupId, weekId, nominationId, triggerVoterId } = input;
  const groupRef = firestore.collection("groups").doc(groupId);
  const weekRef = groupRef.collection("weeks").doc(weekId);
  const nominationRef = weekRef.collection("nominations").doc(nominationId);
  const tallyRef = weekRef.collection("vetoTallies").doc(nominationId);

  const notice = await firestore.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    const weekSnap = await tx.get(weekRef);
    const nominationSnap = await tx.get(nominationRef);
    const votesSnap = await tx.get(nominationRef.collection("vetoVotes"));
    const gamesSnap = await tx.get(weekRef.collection("games"));
    const nominationsSnap = await tx.get(weekRef.collection("nominations"));

    const group = groupSnap.data() as VetoGroupFields | undefined;
    const week = weekSnap.data();
    const nomination = nominationSnap.data();
    const selectorFromNomination = stringField(nomination, "submittedBy");
    const espnEventId = stringField(nomination, "espnEventId") || nominationId;
    const vetoSnap = await readVetoSnap(tx, weekRef, {
      nominationExists: nominationSnap.exists,
      selectorId: selectorFromNomination,
      espnEventId,
    });
    const vetoData = vetoSnap?.data();
    const selectorId = selectorFromNomination || stringField(vetoData, "submittedBy");
    const gameId = stringField(vetoData, "espnEventId") || espnEventId;
    const teams = { ...(vetoData ?? {}), ...(nomination ?? {}) };

    const plan = planSelectionVeto({
      nowMs: Date.now(),
      vetoEnabled: group?.rules?.vetoEnabled === true,
      configuredVotesNeeded: group?.rules?.vetoVotesNeeded,
      memberIds: memberIdList(group?.memberIds),
      weekStatus: week?.status,
      weekSelectionMode: week?.selectionMode,
      groupSelectionMode: group?.rules?.selectionMode,
      selectionDeadlineMs: deadlineMillis(week?.selectionDeadline),
      kickoffMs: deadlineMillis(nomination?.kickoff),
      selectorId,
      voterIds: votesSnap.docs.map((doc) => doc.id),
      triggerVoterId,
      nominationExists: nominationSnap.exists,
      vetoRecorded: vetoSnap?.exists === true,
      vetoNotified: vetoData?.notified === true,
    });

    const vetoId = vetoSnap?.id || (selectorId ? selectionVetoRecordId(selectorId, gameId) : "");
    const vetoRef = vetoId ? weekRef.collection("vetoes").doc(vetoId) : null;
    const away = teamTag(teams.awayTeamAbbreviation, teams.awayTeamName, "AWAY");
    const home = teamTag(teams.homeTeamAbbreviation, teams.homeTeamName, "HOME");
    const builtNotice: VetoNotice | null =
      vetoId && selectorId
        ? {
            groupId,
            weekId,
            gameId,
            selectorId,
            memberIds: memberIdList(group?.memberIds),
            gameLabel: selectionMatchupLabel(teams),
            leagueName: leagueDisplayName(group?.name),
            away,
            home,
            vetoId,
          }
        : null;

    return commitPlan(tx, plan, {
      triggerVoterId,
      nominationRef,
      weekRef,
      tallyRef,
      vetoRef,
      votes: votesSnap.docs,
      gameIds: slateGameIdsForEvent(
        gamesSnap.docs.map((doc) => ({ id: doc.id, espnEventId: doc.data().espnEventId })),
        gameId
      ),
      gamesCollection: weekRef.collection("games"),
      nominationCount: nominationCountAfterRemoval(
        nominationsSnap.docs.map((doc) => doc.id),
        nominationId
      ),
      record:
        plan.kind === "apply"
          ? {
              id: vetoId,
              submittedBy: selectorId,
              submitterName: stringField(nomination, "submitterName") || "A member",
              espnEventId: gameId,
              awayTeamName: stringField(nomination, "awayTeamName"),
              awayTeamAbbreviation: stringField(nomination, "awayTeamAbbreviation"),
              homeTeamName: stringField(nomination, "homeTeamName"),
              homeTeamAbbreviation: stringField(nomination, "homeTeamAbbreviation"),
              voteCount: plan.count,
              votesNeeded: plan.votesNeeded,
              createdAt: FieldValue.serverTimestamp(),
              notified: false,
            }
          : null,
      notice: builtNotice,
    });
  });

  if (notice) await deliverSelectionVeto(firestore, notice);
}

async function readVetoSnap(
  tx: Transaction,
  weekRef: DocumentReference,
  input: { nominationExists: boolean; selectorId: string; espnEventId: string }
) {
  if (input.nominationExists && input.selectorId) {
    return tx.get(weekRef.collection("vetoes").doc(selectionVetoRecordId(input.selectorId, input.espnEventId)));
  }
  if (input.nominationExists) return null;
  const found = await tx.get(
    weekRef.collection("vetoes").where("espnEventId", "==", input.espnEventId).limit(10)
  );
  const index = indexOfPendingVetoRecord(found.docs.map((doc) => doc.data()));
  return index >= 0 ? (found.docs[index] ?? null) : null;
}

function commitPlan(
  tx: Transaction,
  plan: SelectionVetoPlan,
  ctx: {
    triggerVoterId: string | null;
    nominationRef: DocumentReference;
    weekRef: DocumentReference;
    tallyRef: DocumentReference;
    vetoRef: DocumentReference | null;
    votes: QueryDocumentSnapshot[];
    gameIds: string[];
    gamesCollection: CollectionReference;
    nominationCount: number;
    record: Record<string, unknown> | null;
    notice: VetoNotice | null;
  }
): VetoNotice | null {
  if (plan.kind === "drop_trigger_vote" && ctx.triggerVoterId) {
    tx.delete(ctx.nominationRef.collection("vetoVotes").doc(ctx.triggerVoterId));
    return null;
  }
  if (plan.kind === "tally") {
    tx.set(ctx.tallyRef, { count: plan.count, votesNeeded: plan.votesNeeded });
    return null;
  }
  if (plan.kind === "apply" && ctx.vetoRef && ctx.record) {
    tx.delete(ctx.nominationRef);
    for (const gameId of ctx.gameIds) tx.delete(ctx.gamesCollection.doc(gameId));
    for (const vote of ctx.votes) tx.delete(vote.ref);
    tx.set(ctx.vetoRef, ctx.record);
    tx.set(ctx.weekRef, { nominationCount: ctx.nominationCount }, { merge: true });
    tx.delete(ctx.tallyRef);
    return ctx.notice;
  }
  if (plan.kind === "notify_only") return ctx.notice;
  return null;
}

async function deliverSelectionVeto(firestore: Firestore, notice: VetoNotice): Promise<void> {
  const messages = selectionVetoMessages(notice.gameLabel, notice.leagueName);
  const presentation = buildSelectionVetoPush({
    leagueName: notice.leagueName,
    groupId: notice.groupId,
    weekId: notice.weekId,
    gameId: notice.gameId,
    away: notice.away,
    home: notice.home,
  });
  const recipients = notice.memberIds.length > 0 ? notice.memberIds : [notice.selectorId];
  await Promise.all(
    recipients.map((userId) => {
      const copy = userId === notice.selectorId ? messages.selector : messages.league;
      return sendToUser(
        userId,
        copy.title,
        copy.body,
        "selection_veto",
        presentation.data,
        undefined,
        presentation
      );
    })
  );
  await firestore
    .collection("groups")
    .doc(notice.groupId)
    .collection("weeks")
    .doc(notice.weekId)
    .collection("vetoes")
    .doc(notice.vetoId)
    .set({ notified: true }, { merge: true });
  logger.info("selection_veto", {
    groupId: notice.groupId,
    weekId: notice.weekId,
    gameId: notice.gameId,
    selectorId: notice.selectorId,
    recipients: recipients.length,
  });
}

function stringField(data: DocumentData | undefined, key: string): string {
  const value = data?.[key];
  return typeof value === "string" ? value.trim() : "";
}
