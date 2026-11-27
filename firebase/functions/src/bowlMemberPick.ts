/** Member pick writes for Mode B (full bowl catalog) — avoids 20-game rules unroll cap. */

import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { isBowlFullSlateWeek } from "./bowlWeek";
import { gameIsLocked, kickoffMillis } from "./pickLock";
import { rejectedPickIds, type GameLockInput } from "./spreadLock";

const db = () => getFirestore();

function requireAuth(request: { auth?: { uid?: string } }): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to save Pickems.");
  return uid;
}

function requireString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `\`${label}\` is required.`);
  }
  return value.trim();
}

/** Write or merge a member's pick sheet on a full-catalog bowl week. */
export const writeMemberBowlPick = onCall(async (request) => {
  const userId = requireAuth(request);
  const data = (request.data ?? {}) as {
    groupId?: string;
    weekId?: string;
    picks?: Record<string, string>;
    confidenceGameId?: string | null;
    isLocked?: boolean;
  };
  const groupId = requireString(data.groupId, "groupId");
  const weekId = requireString(data.weekId, "weekId");
  const picks = data.picks ?? {};
  if (typeof picks !== "object" || Array.isArray(picks)) {
    throw new HttpsError("invalid-argument", "`picks` must be a map of gameId -> teamId.");
  }
  for (const [gameId, teamId] of Object.entries(picks)) {
    if (typeof teamId !== "string" || teamId.length === 0) {
      throw new HttpsError("invalid-argument", `Pick for game ${gameId} must be a team id string.`);
    }
  }

  const groupRef = db().collection("groups").doc(groupId);
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) throw new HttpsError("not-found", "League not found.");
  const memberIds = (groupSnap.data()?.memberIds as string[] | undefined) ?? [];
  if (!memberIds.includes(userId)) {
    throw new HttpsError("permission-denied", "You are not in this league.");
  }

  const weekRef = groupRef.collection("weeks").doc(weekId);
  const weekSnap = await weekRef.get();
  if (!weekSnap.exists) throw new HttpsError("not-found", "Week not found.");
  const week = weekSnap.data() ?? {};
  if (!isBowlFullSlateWeek(week as { bowlFullSlate?: boolean; slateSource?: string })) {
    throw new HttpsError("failed-precondition", "This week does not use the full bowl pick path.");
  }
  if (week.status !== "picking") {
    throw new HttpsError("failed-precondition", "Pickems are not open for this week.");
  }

  const gamesSnap = await weekRef.collection("games").get();
  const slateIds = new Set(gamesSnap.docs.map((doc) => doc.id));
  for (const gameId of Object.keys(picks)) {
    if (!slateIds.has(gameId)) {
      throw new HttpsError("invalid-argument", `Game ${gameId} is not on this bowl slate.`);
    }
  }

  const lockSnap = await weekRef.collection("gameLock").doc("current").get();
  const lockData = lockSnap.data() ?? {};
  const mirrorKickoffs = (lockData.kickoffs as Record<string, unknown> | undefined) ?? {};
  const weekKickoffs = (week.gameKickoffs as Record<string, unknown> | undefined) ?? {};
  const mergedKickoffs: Record<string, unknown> = { ...weekKickoffs, ...mirrorKickoffs };

  const games: Array<GameLockInput & { id: string }> = gamesSnap.docs.map((gameDoc) => {
    const gameData = gameDoc.data();
    const stamped = mergedKickoffs[gameDoc.id];
    const kickoff = stamped ?? gameData.kickoff;
    return { id: gameDoc.id, kickoff, status: gameData.status };
  });

  const pickRef = weekRef.collection("picks").doc(userId);
  const pickSnap = await pickRef.get();
  const before = pickSnap.data() ?? null;
  const beforePicks = (before?.picks as Record<string, string> | undefined) ?? {};
  const now = Date.now();
  const weekForLock = {
    ...week,
    gameKickoffs: Object.fromEntries(
      Object.entries(mergedKickoffs).flatMap(([id, value]) => {
        const ms = kickoffMillis(value);
        return ms == null ? [] : [[id, Timestamp.fromMillis(ms)]];
      })
    ),
    allowLatePicks: groupSnap.data()?.rules?.allowLatePicks === true,
  };

  const blocked = rejectedPickIds({
    week: weekForLock,
    games,
    before: beforePicks,
    after: picks,
    now,
    beforeConfidence: before?.confidenceGameId,
    afterConfidence: data.confidenceGameId ?? before?.confidenceGameId ?? null,
  });
  if (blocked.length > 0) {
    throw new HttpsError("failed-precondition", `Picks are locked for: ${blocked.join(", ")}.`);
  }

  const memberSnap = await groupRef.collection("members").doc(userId).get();
  const displayName = (memberSnap.data()?.displayName as string | undefined) ?? "Unknown";
  const isLocked = data.isLocked ?? (before?.isLocked as boolean | undefined) ?? false;

  const payload: Record<string, unknown> = {
    id: userId,
    userId,
    displayName,
    picks,
    isLocked,
    confidenceGameId: data.confidenceGameId ?? before?.confidenceGameId ?? null,
    submittedAt: isLocked ? before?.submittedAt ?? FieldValue.serverTimestamp() : null,
  };
  await pickRef.set(payload, { merge: true });

  await weekRef.collection("submissions").doc(userId).set(
    {
      id: userId,
      userId,
      displayName,
      isLocked,
      submittedAt: isLocked ? before?.submittedAt ?? FieldValue.serverTimestamp() : null,
    },
    { merge: true }
  );

  return { groupId, weekId, userId, pickCount: Object.keys(picks).length, isLocked };
});