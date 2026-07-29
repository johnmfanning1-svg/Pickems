import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentUpdated, onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { fetchScoreboard, parseEventScores } from "./espn";
import { sendToUser, sendToUsers } from "./notifications";
import {
  SlateGameDoc,
  MemberDoc,
  PickDoc,
  coveredTeamId,
  scorePicks,
  rankEntries,
  computeWeekAwards,
} from "./scoring";
import { materializeNominations } from "./materialize";

admin.initializeApp();
const db = admin.firestore();

// Callable admin surface for the web portal — claim-gated, audit-logged.
export {
  setAdminRole,
  adminSetWeekStatus,
  adminRematerializeNominations,
  adminUpsertPick,
  adminRemoveMember,
  adminTransferCommissioner,
  adminAuditWeekIds,
  adminRescoreWeek,
} from "./admin";

// Group chat — push fan-out plus the report counter clients cannot write.
export { onMessageCreated, onReportCreated } from "./chat";

/** When a week flips to picking, materialize nominations into games if needed. */
export const onWeekStatusChange = onDocumentUpdated(
  "groups/{groupId}/weeks/{weekId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;

    const groupId = event.params.groupId;
    const weekId = event.params.weekId;

    if (after.status === "picking" && before.status === "selection") {
      await materializeNominations(groupId, weekId);
    }

    if (after.status === "scored" && before.status !== "scored") {
      const group = await db.collection("groups").doc(groupId).get();
      const memberIds = (group.data()?.memberIds as string[]) ?? [];
      await sendToUsers(
        memberIds,
        "Week locked in",
        `Week ${after.weekNumber} is scored — check the leaderboard.`,
        "week_scored",
        { groupId, weekId }
      );
    }
  }
);

/** Reminder ~2h before deadline for weeks still in picking. */
export const deadlineReminders = onSchedule("every 15 minutes", async () => {
  const now = admin.firestore.Timestamp.now();
  const inTwoHours = admin.firestore.Timestamp.fromMillis(now.toMillis() + 2 * 60 * 60 * 1000);
  const groups = await db.collection("groups").get();

  for (const groupDoc of groups.docs) {
    const weeks = await groupDoc.ref
      .collection("weeks")
      .where("status", "==", "picking")
      .get();

    for (const weekDoc of weeks.docs) {
      const week = weekDoc.data();
      const deadline = week.pickDeadline as admin.firestore.Timestamp | undefined;
      if (!deadline) continue;
      if (deadline.toMillis() < now.toMillis() || deadline.toMillis() > inTwoHours.toMillis()) {
        continue;
      }
      if (week.deadlineReminderSent) continue;

      const memberIds = (groupDoc.data().memberIds as string[]) ?? [];
      const submissions = await weekDoc.ref.collection("submissions").get();
      const submitted = new Set(
        submissions.docs.filter((d) => d.data().isLocked === true).map((d) => d.id)
      );
      const pending = memberIds.filter((id) => !submitted.has(id));
      await sendToUsers(
        pending,
        "Pick deadline soon",
        `Submit your Week ${week.weekNumber} picks before kickoff.`,
        "deadline_reminder",
        { groupId: groupDoc.id, weekId: weekDoc.id }
      );
      await weekDoc.ref.update({ deadlineReminderSent: true });
    }
  }
});

/** Lock weeks past deadline; score finals from ESPN. */
export const lockAndScoreWeeks = onSchedule("every 5 minutes", async () => {
  const now = Date.now();
  const groups = await db.collection("groups").get();
  const events = await fetchScoreboard().catch((err) => {
    logger.error("ESPN fetch failed", err);
    return [] as Awaited<ReturnType<typeof fetchScoreboard>>;
  });
  const eventById = new Map(events.map((e) => [e.id, e]));

  for (const groupDoc of groups.docs) {
    const groupId = groupDoc.id;
    const memberIds = (groupDoc.data().memberIds as string[]) ?? [];

    const activeWeeks = await groupDoc.ref
      .collection("weeks")
      .where("status", "in", ["picking", "locked"])
      .get();

    for (const weekDoc of activeWeeks.docs) {
      const week = weekDoc.data();
      const weekId = weekDoc.id;
      const deadline = week.pickDeadline as admin.firestore.Timestamp | undefined;

      if (week.status === "picking" && deadline && deadline.toMillis() <= now) {
        await weekDoc.ref.update({
          status: "locked",
          lockedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await sendToUsers(
          memberIds,
          "Picks are locked",
          `Week ${week.weekNumber} is locked. Good luck.`,
          "deadline_locked",
          { groupId, weekId }
        );
      }

      const gamesSnap = await weekDoc.ref.collection("games").get();
      if (gamesSnap.empty) {
        if (week.status === "picking") {
          await materializeNominations(groupId, weekId);
        }
        continue;
      }

      let anyFinalizedThisPass = false;
      const updatedGames: SlateGameDoc[] = [];
      for (const gameDoc of gamesSnap.docs) {
        const game = { id: gameDoc.id, ...gameDoc.data() } as unknown as SlateGameDoc;
        const event = eventById.get(game.espnEventId);
        if (!event) {
          updatedGames.push(game);
          continue;
        }
        const parsed = parseEventScores(event);
        if (!parsed) {
          updatedGames.push(game);
          continue;
        }

        const prevStatus = game.status;
        let nextStatus = game.status;
        if (parsed.completed) nextStatus = "final";
        else if (parsed.inProgress) nextStatus = "inProgress";

        const patch: Partial<SlateGameDoc> = {
          status: nextStatus,
          homeScore: parsed.homeScore,
          awayScore: parsed.awayScore,
        };
        if (nextStatus === "final") {
          patch.winnerTeamId = coveredTeamId(game, parsed.homeScore, parsed.awayScore);
        }
        if (prevStatus !== nextStatus || game.homeScore !== parsed.homeScore) {
          await gameDoc.ref.update(patch);
          if (prevStatus !== "final" && nextStatus === "final") {
            anyFinalizedThisPass = true;
            await notifyGameFinal(groupId, weekId, { ...game, ...patch } as SlateGameDoc);
          }
        }
        updatedGames.push({ ...game, ...patch } as SlateGameDoc);
      }

      const allFinal =
        updatedGames.length > 0 && updatedGames.every((g) => g.status === "final");
      if ((week.status === "locked" || week.status === "picking") && allFinal) {
        await scoreWeek(groupId, weekId, week.weekNumber as number, updatedGames, memberIds);
      } else if (anyFinalizedThisPass && week.status === "locked") {
        await refreshLiveStandings(groupId, weekId, week.weekNumber as number, updatedGames);
      }
    }
  }
});

async function notifyGameFinal(
  groupId: string,
  weekId: string,
  game: SlateGameDoc
): Promise<void> {
  const picksSnap = await db
    .collection("groups")
    .doc(groupId)
    .collection("weeks")
    .doc(weekId)
    .collection("picks")
    .get();

  const covered = game.winnerTeamId;
  const label = `${game.awayTeamAbbreviation ?? "AWAY"} @ ${game.homeTeamAbbreviation ?? "HOME"}`;

  for (const pickDoc of picksSnap.docs) {
    const pick = pickDoc.data() as PickDoc;
    const chosen = pick.picks?.[game.id];
    if (!chosen) continue;
    let result = "push";
    if (covered && covered === chosen) result = "covered";
    else if (covered) result = "missed";
    await sendToUser(
      pick.userId,
      result === "covered" ? "You covered" : result === "missed" ? "Tough beat" : "Push",
      `${label} is final.`,
      "game_final",
      { groupId, weekId, gameId: game.id, result }
    );
  }
}

async function refreshLiveStandings(
  groupId: string,
  weekId: string,
  weekNumber: number,
  games: SlateGameDoc[]
): Promise<void> {
  const [membersSnap, picksSnap, standingsSnap] = await Promise.all([
    db.collection("groups").doc(groupId).collection("members").get(),
    db.collection("groups").doc(groupId).collection("weeks").doc(weekId).collection("picks").get(),
    db.collection("groups").doc(groupId).collection("standings").doc("current").get(),
  ]);

  const previousRanks = new Map<string, number>();
  const prev = standingsSnap.data()?.entries as Array<{ id: string; rank: number }> | undefined;
  prev?.forEach((e) => previousRanks.set(e.id, e.rank));

  const members = membersSnap.docs.map((d) => ({ id: d.id, ...d.data() } as MemberDoc));
  const picks = picksSnap.docs.map((d) => ({ ...(d.data() as PickDoc), userId: d.id }));

  const entries = members.map((member) => {
    const pick = picks.find((p) => p.userId === member.id);
    const scored = scorePicks(pick?.picks ?? {}, games, pick?.confidenceGameId);
    return {
      id: member.id,
      displayName: member.displayName,
      avatarColorHex: member.avatarColorHex ?? "#DC2626",
      weeklyWins: scored.wins,
      weeklyLosses: scored.losses,
      seasonWins: member.seasonWins ?? 0,
      seasonLosses: member.seasonLosses ?? 0,
    };
  });

  const ranked = rankEntries(entries);
  await db
    .collection("groups")
    .doc(groupId)
    .collection("standings")
    .doc("current")
    .set({
      groupId,
      weekNumber,
      entries: ranked,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  for (const entry of ranked) {
    const prevRank = previousRanks.get(entry.id);
    if (prevRank != null && prevRank > 1 && entry.rank === 1) {
      await sendToUser(
        entry.id,
        "You took the lead",
        "You're #1 on the live board.",
        "took_the_lead",
        { groupId, weekId }
      );
    }
  }
}

async function scoreWeek(
  groupId: string,
  weekId: string,
  weekNumber: number,
  games: SlateGameDoc[],
  memberIds: string[]
): Promise<void> {
  const membersSnap = await db.collection("groups").doc(groupId).collection("members").get();
  const picksSnap = await db
    .collection("groups")
    .doc(groupId)
    .collection("weeks")
    .doc(weekId)
    .collection("picks")
    .get();

  const members = membersSnap.docs.map((d) => ({ id: d.id, ...d.data() } as MemberDoc));
  const picks = picksSnap.docs.map((d) => ({ ...(d.data() as PickDoc), userId: d.id }));
  const awards = computeWeekAwards(picks, games);

  const batch = db.batch();
  const weeklyEntries = [];

  for (const member of members) {
    const pick = picks.find((p) => p.userId === member.id);
    const scored = scorePicks(pick?.picks ?? {}, games, pick?.confidenceGameId);
    const seasonWins = (member.seasonWins ?? 0) + scored.wins;
    const seasonLosses = (member.seasonLosses ?? 0) + scored.losses;
    batch.update(db.collection("groups").doc(groupId).collection("members").doc(member.id), {
      seasonWins,
      seasonLosses,
    });
    weeklyEntries.push({
      id: member.id,
      displayName: member.displayName,
      avatarColorHex: member.avatarColorHex ?? "#DC2626",
      weeklyWins: scored.wins,
      weeklyLosses: scored.losses,
      seasonWins,
      seasonLosses,
    });
  }

  const ranked = rankEntries(weeklyEntries);
  batch.set(db.collection("groups").doc(groupId).collection("standings").doc("current"), {
    groupId,
    weekNumber,
    entries: ranked,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  batch.update(db.collection("groups").doc(groupId).collection("weeks").doc(weekId), {
    status: "scored",
    awards,
    scoredAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
  logger.info(`Scored week ${weekId} for group ${groupId}`, awards);
  void memberIds;
}

/** Auto-close seasons after CFB championship window (early January). */
export const autoCloseSeasons = onSchedule("0 12 15 1 *", async () => {
  const year = new Date().getFullYear() - 1;
  const groups = await db.collection("groups").get();
  for (const groupDoc of groups.docs) {
    const existing = await groupDoc.ref.collection("seasons").doc(String(year)).get();
    if (existing.exists) continue;

    const membersSnap = await groupDoc.ref.collection("members").get();
    const members = membersSnap.docs.map((d) => ({ id: d.id, ...d.data() } as MemberDoc));
    if (members.length === 0) continue;

    const sorted = [...members].sort((a, b) => {
      if ((b.seasonWins ?? 0) !== (a.seasonWins ?? 0)) {
        return (b.seasonWins ?? 0) - (a.seasonWins ?? 0);
      }
      return (a.displayName ?? "").localeCompare(b.displayName ?? "");
    });
    const champion = sorted[0];
    const finalStandings = sorted.map((m, index) => ({
      id: m.id,
      displayName: m.displayName,
      avatarColorHex: m.avatarColorHex ?? "#DC2626",
      seasonWins: m.seasonWins ?? 0,
      seasonLosses: m.seasonLosses ?? 0,
      rank: index + 1,
    }));

    const weeks = await groupDoc.ref.collection("weeks").where("seasonYear", "==", year).get();
    const batch = db.batch();
    batch.set(groupDoc.ref.collection("seasons").doc(String(year)), {
      id: String(year),
      seasonYear: year,
      groupId: groupDoc.id,
      championUserId: champion?.id ?? null,
      championDisplayName: champion?.displayName ?? null,
      finalStandings,
      weekCount: weeks.size,
      closedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    for (const member of members) {
      const finish = finalStandings.find((s) => s.id === member.id)?.rank ?? finalStandings.length;
      const wonTitle = champion?.id === member.id;
      const careerRef = groupDoc.ref.collection("career").doc(member.id);
      const careerSnap = await careerRef.get();
      const career = careerSnap.data() ?? {};
      batch.set(careerRef, {
        id: member.id,
        displayName: member.displayName,
        avatarColorHex: member.avatarColorHex ?? "#DC2626",
        titles: (career.titles ?? 0) + (wonTitle ? 1 : 0),
        seasonWins: (career.seasonWins ?? 0) + (member.seasonWins ?? 0),
        seasonLosses: (career.seasonLosses ?? 0) + (member.seasonLosses ?? 0),
        seasonsPlayed: (career.seasonsPlayed ?? 0) + 1,
        bestFinish:
          career.bestFinish == null ? finish : Math.min(career.bestFinish as number, finish),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      batch.update(groupDoc.ref.collection("members").doc(member.id), {
        seasonWins: 0,
        seasonLosses: 0,
      });
    }

    await batch.commit();
    const memberIds = (groupDoc.data().memberIds as string[]) ?? [];
    await sendToUsers(
      memberIds,
      `${year} season closed`,
      champion
        ? `${champion.displayName} is your ${year} champion.`
        : `Season ${year} is archived.`,
      "season_closed",
      { groupId: groupDoc.id, seasonYear: String(year) }
    );
  }
});

/** Keep public league index in sync when isPublic flips. */
export const syncPublicLeagueIndex = onDocumentUpdated("groups/{groupId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  const groupId = event.params.groupId;
  const indexRef = db.collection("publicLeagues").doc(groupId);
  if (after.isPublic === true) {
    await indexRef.set({
      groupId,
      name: after.name,
      inviteCode: after.inviteCode,
      memberCount: (after.memberIds as string[] | undefined)?.length ?? 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } else if (before.isPublic === true && after.isPublic !== true) {
    await indexRef.delete();
  }
});

export const onPublicLeagueCreated = onDocumentCreated("groups/{groupId}", async (event) => {
  const data = event.data?.data();
  if (!data?.isPublic) return;
  await db
    .collection("publicLeagues")
    .doc(event.params.groupId)
    .set({
      groupId: event.params.groupId,
      name: data.name,
      inviteCode: data.inviteCode,
      memberCount: (data.memberIds as string[] | undefined)?.length ?? 0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
});
