import { FieldValue, Timestamp } from "firebase-admin/firestore";

export function resolvedPickLockMode(value: unknown): "firstKickoff" | "rolling" {
  return value === "rolling" ? "rolling" : "firstKickoff";
}

export function isRollingLock(value: unknown): boolean {
  return resolvedPickLockMode(value) === "rolling";
}

export function kickoffMillis(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isFinite(ms) ? ms : null;
  }
  if (typeof value === "object" && value !== null && "toMillis" in value) {
    const ms = (value as { toMillis: () => number }).toMillis();
    return Number.isFinite(ms) ? ms : null;
  }
  return null;
}

export function lockSnapshotFromGames(
  games: Array<{ id: string; kickoff?: unknown }>,
  pickLockMode: unknown
): Record<string, unknown> {
  const mode = resolvedPickLockMode(pickLockMode);
  const pairs = games
    .map((game) => {
      const ms = kickoffMillis(game.kickoff);
      return ms == null ? null : { id: game.id, ms };
    })
    .filter((pair): pair is { id: string; ms: number } => pair != null)
    .slice(0, 20);

  const fields: Record<string, unknown> = { pickLockMode: mode };
  if (pairs.length === 0) return fields;

  const first = Math.min(...pairs.map((pair) => pair.ms));
  const last = Math.max(...pairs.map((pair) => pair.ms));
  const gameKickoffs: Record<string, Timestamp> = {};
  const gameIds: string[] = [];
  for (const pair of pairs) {
    gameIds.push(pair.id);
    gameKickoffs[pair.id] = Timestamp.fromMillis(pair.ms);
  }

  fields.pickDeadline = Timestamp.fromMillis(first);
  fields.weekLockAt = Timestamp.fromMillis(mode === "rolling" ? last : first);
  fields.gameIds = gameIds;
  fields.gameKickoffs = gameKickoffs;
  return fields;
}

export function effectiveWeekLockMillis(week: {
  pickLockMode?: unknown;
  weekLockAt?: unknown;
  remainingLockAt?: unknown;
  pickDeadline?: unknown;
}): number | null {
  const weekLock = kickoffMillis(week.weekLockAt);
  const remaining = kickoffMillis(week.remainingLockAt);
  if (weekLock != null && remaining != null) return Math.min(weekLock, remaining);
  if (weekLock != null) return weekLock;
  if (remaining != null) return remaining;
  if (isRollingLock(week.pickLockMode)) return null;
  return kickoffMillis(week.pickDeadline);
}

export function gameIsLocked(
  week: {
    pickLockMode?: unknown;
    remainingLockAt?: unknown;
    pickDeadline?: unknown;
    gameKickoffs?: Record<string, unknown>;
  },
  gameId: string,
  kickoff: unknown,
  now: number
): boolean {
  const remaining = kickoffMillis(week.remainingLockAt);
  if (remaining != null && now >= remaining) return true;
  if (isRollingLock(week.pickLockMode)) {
    const stamped = week.gameKickoffs?.[gameId];
    const ms = kickoffMillis(stamped) ?? kickoffMillis(kickoff);
    return ms != null && now >= ms;
  }
  const deadline = kickoffMillis(week.pickDeadline);
  return deadline != null && now >= deadline;
}

export function revealedPicksForGame(
  gameId: string,
  pickDocs: Array<{
    id: string;
    picks?: Record<string, string>;
    confidenceGameId?: string;
  }>
): { picks: Record<string, string>; confidenceUserIds: string[] } {
  const picks: Record<string, string> = {};
  const confidenceUserIds: string[] = [];
  for (const pickDoc of pickDocs) {
    const team = pickDoc.picks?.[gameId];
    if (typeof team === "string" && team.length > 0) {
      picks[pickDoc.id] = team;
    }
    if (pickDoc.confidenceGameId === gameId) {
      confidenceUserIds.push(pickDoc.id);
    }
  }
  return { picks, confidenceUserIds };
}

export async function revealLockedGames(options: {
  weekRef: FirebaseFirestore.DocumentReference;
  week: FirebaseFirestore.DocumentData;
  games: { docs: Array<{ id: string; data: () => FirebaseFirestore.DocumentData }> };
  now: number;
}): Promise<number> {
  const { weekRef, week, games, now } = options;
  if (!isRollingLock(week.pickLockMode)) return 0;

  const picksSnap = await weekRef.collection("picks").get();
  const pickDocs = picksSnap.docs.map((pickDoc) => ({
    id: pickDoc.id,
    picks: pickDoc.data().picks as Record<string, string> | undefined,
    confidenceGameId: pickDoc.data().confidenceGameId as string | undefined,
  }));
  let revealed = 0;
  for (const gameDoc of games.docs) {
    if (!gameIsLocked(week, gameDoc.id, gameDoc.data().kickoff, now)) continue;
    const payload = revealedPicksForGame(gameDoc.id, pickDocs);
    await weekRef.collection("revealedPicks").doc(gameDoc.id).set({
      ...payload,
      revealedAt: FieldValue.serverTimestamp(),
    });
    revealed += 1;
  }
  return revealed;
}

export function lastKickoffMillis(
  games: Array<{ kickoff?: unknown }>
): number | null {
  const times = games
    .map((game) => kickoffMillis(game.kickoff))
    .filter((ms): ms is number => ms != null);
  return times.length ? Math.max(...times) : null;
}
