import * as admin from "firebase-admin";
import { fetchScoreboard, resolveSpreadTeamId, type EspnEvent } from "./espn";
import {
  WEEK_ONE_ID,
  WEEK_ZERO_ID,
  WEEK_ZERO_SLATE_SOURCE,
  WEEK_ZERO_YEAR,
  earliestKickoff,
  isWeekZeroKickoff,
  splitPickMap,
  submissionCoversSlate,
} from "./cfbWeekCalendar";
import { lockSnapshotFromGames } from "./pickLock";

export interface Week0SplitGroupResult {
  groupId: string;
  groupName: string | null;
  skipped: boolean;
  skipReason?: string;
  weekZeroGames: number;
  movedNominations: number;
  movedPickDocs: number;
  deletedWeekOneGames: number;
  clearedSubmissions: number;
  weekOnePickDeadline: string | null;
}

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

function asDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === "object" && value !== null && "toDate" in value) {
    const toDate = (value as { toDate?: () => Date }).toDate;
    if (typeof toDate === "function") return toDate.call(value);
  }
  return null;
}

function competitor(
  event: EspnEvent,
  homeAway: "home" | "away"
): NonNullable<NonNullable<EspnEvent["competitions"]>[number]["competitors"]>[number] | null {
  return event.competitions?.[0]?.competitors?.find((c) => c.homeAway === homeAway) ?? null;
}

function eventKickoff(event: EspnEvent): Date | null {
  if (!event.date) return null;
  const parsed = new Date(event.date);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function eventIsWeekZero(event: EspnEvent, kickoffFromDoc?: Date | null): boolean {
  const kickoff = kickoffFromDoc ?? eventKickoff(event);
  return kickoff != null && isWeekZeroKickoff(kickoff);
}

function slatePayloadFromEspn(event: EspnEvent): Record<string, unknown> | null {
  const home = competitor(event, "home");
  const away = competitor(event, "away");
  const kickoff = eventKickoff(event);
  if (!home || !away || !kickoff) return null;
  const competition = event.competitions?.[0];
  const odds = competition?.odds?.[0];
  const signedSpread = typeof odds?.spread === "number" ? odds.spread : 0;
  const rawSpread = Math.abs(signedSpread);
  const spreadTeamId = resolveSpreadTeamId({
    homeTeamId: home.team.id,
    awayTeamId: away.team.id,
    spread: odds?.spread,
    homeFavorite: odds?.homeTeamOdds?.favorite,
    awayFavorite: odds?.awayTeamOdds?.favorite,
  });
  const national = competition?.broadcasts?.find((b) => (b.market ?? "").toLowerCase() === "national");
  const broadcast =
    national?.names?.[0] ??
    competition?.broadcasts?.[0]?.names?.[0] ??
    competition?.geoBroadcasts?.[0]?.media?.shortName ??
    null;
  return {
    id: event.id,
    espnEventId: event.id,
    homeTeamId: home.team.id,
    homeTeamName: home.team.displayName,
    homeTeamAbbreviation: home.team.abbreviation,
    homeTeamLogoURL: home.team.logo ?? null,
    awayTeamId: away.team.id,
    awayTeamName: away.team.displayName,
    awayTeamAbbreviation: away.team.abbreviation,
    awayTeamLogoURL: away.team.logo ?? null,
    spread: rawSpread,
    spreadTeamId,
    kickoff: admin.firestore.Timestamp.fromDate(kickoff),
    status: "scheduled",
    homeScore: null,
    awayScore: null,
    winnerTeamId: null,
    broadcastLabel: broadcast,
    isNeutralSite: competition?.neutralSite === true,
  };
}

export async function migrateGroupWeek0Split(options: {
  groupId: string;
  espnEvents: EspnEvent[];
  dryRun: boolean;
}): Promise<Week0SplitGroupResult> {
  const { groupId, espnEvents, dryRun } = options;
  const groupRef = db().collection("groups").doc(groupId);
  const groupSnap = await groupRef.get();
  const groupName = (groupSnap.data()?.name as string | undefined) ?? null;
  const weekZeroEvents = espnEvents.filter((event) => eventIsWeekZero(event));
  const weekZeroIds = new Set(weekZeroEvents.map((e) => e.id));

  const w0Ref = groupRef.collection("weeks").doc(WEEK_ZERO_ID);
  const w1Ref = groupRef.collection("weeks").doc(WEEK_ONE_ID);
  const w0Snap = await w0Ref.get();
  const w1Snap = await w1Ref.get();

  const [w1Noms, w1Games, w1Picks, w0Games, w0Picks] = await Promise.all([
    w1Snap.exists ? w1Ref.collection("nominations").get() : Promise.resolve({ docs: [] }),
    w1Snap.exists ? w1Ref.collection("games").get() : Promise.resolve({ docs: [] }),
    w1Snap.exists ? w1Ref.collection("picks").get() : Promise.resolve({ docs: [] }),
    w0Snap.exists ? w0Ref.collection("games").get() : Promise.resolve({ docs: [] }),
    w0Snap.exists ? w0Ref.collection("picks").get() : Promise.resolve({ docs: [] }),
  ]);

  const w1HasWeekZeroGames = w1Games.docs.some((doc) => {
    const kickoff = asDate(doc.data().kickoff);
    return (typeof doc.data().espnEventId === "string" && weekZeroIds.has(doc.data().espnEventId as string))
      || (kickoff != null && isWeekZeroKickoff(kickoff));
  });
  const w1HasWeekZeroNoms = w1Noms.docs.some((doc) => {
    const kickoff = asDate(doc.data().kickoff);
    const eventId = doc.data().espnEventId as string | undefined;
    return (eventId != null && weekZeroIds.has(eventId)) || (kickoff != null && isWeekZeroKickoff(kickoff));
  });

  if (w0Snap.exists && w0Games.docs.length >= 8 && !w1HasWeekZeroGames && !w1HasWeekZeroNoms) {
    return {
      groupId,
      groupName,
      skipped: true,
      skipReason: "alreadySplit",
      weekZeroGames: w0Games.docs.length,
      movedNominations: 0,
      movedPickDocs: 0,
      deletedWeekOneGames: 0,
      clearedSubmissions: 0,
      weekOnePickDeadline: null,
    };
  }

  if (weekZeroEvents.length === 0) {
    return {
      groupId,
      groupName,
      skipped: true,
      skipReason: "espnWeekZeroEmpty",
      weekZeroGames: 0,
      movedNominations: 0,
      movedPickDocs: 0,
      deletedWeekOneGames: 0,
      clearedSubmissions: 0,
      weekOnePickDeadline: null,
    };
  }

  const w1Data = w1Snap.data() ?? {};
  const groupRules = groupSnap.data()?.rules as { pickDeadline?: unknown } | undefined;
  const pickLockMode = groupRules?.pickDeadline;

  const remainingW1Games = w1Games.docs.filter((doc) => {
    const kickoff = asDate(doc.data().kickoff);
    const eventId = (doc.data().espnEventId as string | undefined) ?? doc.id;
    if (weekZeroIds.has(eventId)) return false;
    if (kickoff != null && isWeekZeroKickoff(kickoff)) return false;
    return true;
  });
  const remainingKickoffs = remainingW1Games
    .map((doc) => asDate(doc.data().kickoff))
    .filter((d): d is Date => d != null);
  const remainingDeadline = earliestKickoff(remainingKickoffs);
  const remainingEventIds = remainingW1Games.map(
    (doc) => (doc.data().espnEventId as string | undefined) ?? doc.id
  );

  const nomsToMove = w1Noms.docs.filter((doc) => {
    const kickoff = asDate(doc.data().kickoff);
    const eventId = doc.data().espnEventId as string | undefined;
    return (eventId != null && weekZeroIds.has(eventId)) || (kickoff != null && isWeekZeroKickoff(kickoff));
  });

  const gamesToDelete = w1Games.docs.filter((doc) => {
    const kickoff = asDate(doc.data().kickoff);
    const eventId = (doc.data().espnEventId as string | undefined) ?? doc.id;
    return weekZeroIds.has(eventId) || (kickoff != null && isWeekZeroKickoff(kickoff));
  });

  let movedPickDocs = 0;
  let clearedSubmissions = 0;
  const remainingNomCount = w1Noms.docs.length - nomsToMove.length;

  if (!dryRun) {
    const batch = db().batch();

    const w0Payload: Record<string, unknown> = {
      id: WEEK_ZERO_ID,
      seasonYear: WEEK_ZERO_YEAR,
      weekNumber: 0,
      status: "picking",
      slateSize: weekZeroEvents.length,
      selectionMode: w1Data.selectionMode ?? "member",
      selectionsPerMember: w1Data.selectionsPerMember ?? 3,
      nominationCount: nomsToMove.length,
      slateSource: WEEK_ZERO_SLATE_SOURCE,
      lockedAt: w1Data.lockedAt ?? admin.firestore.FieldValue.serverTimestamp(),
      ...lockSnapshotFromGames(
        weekZeroEvents.map((event) => ({
          id: event.id,
          kickoff: eventKickoff(event),
        })),
        pickLockMode
      ),
    };
    batch.set(w0Ref, w0Payload, { merge: true });

    const w1GameByEvent = new Map<string, admin.firestore.DocumentData>();
    for (const doc of w1Games.docs) {
      const eventId = (doc.data().espnEventId as string | undefined) ?? doc.id;
      w1GameByEvent.set(eventId, doc.data());
    }

    for (const event of weekZeroEvents) {
      const existing = w1GameByEvent.get(event.id);
      const payload = existing
        ? {
            ...existing,
            id: event.id,
            espnEventId: event.id,
            broadcastLabel: existing.broadcastLabel ?? slatePayloadFromEspn(event)?.broadcastLabel ?? null,
            isNeutralSite: existing.isNeutralSite ?? slatePayloadFromEspn(event)?.isNeutralSite ?? false,
          }
        : slatePayloadFromEspn(event);
      if (!payload) continue;
      batch.set(w0Ref.collection("games").doc(event.id), payload, { merge: true });
    }

    for (const nom of nomsToMove) {
      batch.set(w0Ref.collection("nominations").doc(nom.id), nom.data());
      batch.delete(nom.ref);
    }

    const existingW0Picks = new Map<string, Record<string, string>>();
    for (const doc of w0Picks.docs) {
      existingW0Picks.set(doc.id, (doc.data().picks as Record<string, string> | undefined) ?? {});
    }

    for (const pickDoc of w1Picks.docs) {
      const data = pickDoc.data();
      const picks = (data.picks as Record<string, string> | undefined) ?? {};
      const split = splitPickMap(picks, weekZeroIds);
      const mergedW0 = { ...(existingW0Picks.get(pickDoc.id) ?? {}), ...split.weekZero };
      if (Object.keys(split.weekZero).length > 0) {
        batch.set(
          w0Ref.collection("picks").doc(pickDoc.id),
          {
            ...data,
            picks: mergedW0,
          },
          { merge: true }
        );
        movedPickDocs += 1;
      }
      batch.set(pickDoc.ref, { ...data, picks: split.weekOne }, { merge: true });

      if (data.isLocked === true && !submissionCoversSlate(split.weekOne, remainingEventIds)) {
        batch.delete(w1Ref.collection("submissions").doc(pickDoc.id));
        batch.set(pickDoc.ref, { ...data, picks: split.weekOne, isLocked: false }, { merge: true });
        clearedSubmissions += 1;
      }
    }

    for (const game of gamesToDelete) {
      batch.delete(game.ref);
    }

    const w1Updates: Record<string, unknown> = {
      nominationCount: remainingNomCount,
    };
    if (remainingW1Games.length === 0 && (w1Data.status === "picking" || w1Data.status === "locked")) {
      w1Updates.status = "selection";
      w1Updates.pickDeadline = admin.firestore.FieldValue.delete();
      w1Updates.lockedAt = admin.firestore.FieldValue.delete();
    } else if (remainingW1Games.length > 0 && (w1Data.status === "picking" || w1Data.status === "locked")) {
      Object.assign(
        w1Updates,
        lockSnapshotFromGames(
          remainingW1Games.map((doc) => ({
            id: doc.id,
            kickoff: doc.data().kickoff,
          })),
          (w1Data.pickLockMode as string | undefined) ?? pickLockMode
        )
      );
    }
    if (w1Snap.exists) {
      batch.update(w1Ref, w1Updates);
    }

    await batch.commit();
  } else {
    movedPickDocs = w1Picks.docs.filter((doc) => {
      const picks = (doc.data().picks as Record<string, string> | undefined) ?? {};
      return Object.keys(picks).some((id) => weekZeroIds.has(id));
    }).length;
    clearedSubmissions = w1Picks.docs.filter((doc) => {
      const data = doc.data();
      if (data.isLocked !== true) return false;
      const picks = (data.picks as Record<string, string> | undefined) ?? {};
      const split = splitPickMap(picks, weekZeroIds);
      return !submissionCoversSlate(split.weekOne, remainingEventIds);
    }).length;
  }

  return {
    groupId,
    groupName,
    skipped: false,
    weekZeroGames: weekZeroEvents.length,
    movedNominations: nomsToMove.length,
    movedPickDocs,
    deletedWeekOneGames: gamesToDelete.length,
    clearedSubmissions,
    weekOnePickDeadline: remainingDeadline?.toISOString() ?? null,
  };
}

export async function migrateAllGroupsWeek0Split(options: {
  dryRun: boolean;
  groupId?: string;
}): Promise<{ dryRun: boolean; groups: Week0SplitGroupResult[] }> {
  const espnEvents = await fetchScoreboard({ week: 1, seasonType: 2 });
  const groupSnaps = options.groupId
    ? [await db().collection("groups").doc(options.groupId).get()]
    : (await db().collection("groups").get()).docs;

  const groups: Week0SplitGroupResult[] = [];
  for (const snap of groupSnaps) {
    if (!snap.exists) continue;
    groups.push(
      await migrateGroupWeek0Split({
        groupId: snap.id,
        espnEvents,
        dryRun: options.dryRun,
      })
    );
  }
  return { dryRun: options.dryRun, groups };
}
