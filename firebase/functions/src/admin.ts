import * as admin from "firebase-admin";
import { onCall, CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { materializeNominations } from "./materialize";
import {
  SlateGameDoc,
  MemberDoc,
  PickDoc,
  scorePicks,
  rankEntries,
  computeWeekAwards,
  applyLatePickPenalty,
} from "./scoring";

/**
 * Callable surface for the web admin portal (Lane J).
 *
 * Every function here is gated on the `admin` custom claim and appends an
 * `adminAudit` entry, so the portal can never take a privileged action that
 * leaves no trail. Scoring always routes through ./scoring so the portal and
 * `lockAndScoreWeeks` can never disagree.
 */

/** Lazy — `admin.initializeApp()` runs in index.ts after this module is loaded. */
function db(): admin.firestore.Firestore {
  return admin.firestore();
}

const WEEK_STATUSES = ["selection", "picking", "locked", "scored"] as const;
type WeekStatus = (typeof WEEK_STATUSES)[number];

interface Actor {
  uid: string;
  email: string | null;
}

function requireSuperAdmin(request: CallableRequest): Actor {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  if (auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "This account is not authorized.");
  }
  return { uid: auth.uid, email: (auth.token.email as string | undefined) ?? null };
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `\`${field}\` is required.`);
  }
  return value.trim();
}

/**
 * Firestore rejects `undefined` and cannot store class instances, so audit
 * payloads are flattened to plain JSON-safe values before being written.
 */
function auditable(value: unknown, depth = 0): unknown {
  if (value === undefined) return null;
  if (value === null) return null;
  if (value instanceof admin.firestore.Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (depth >= 6) return String(value);
  if (Array.isArray(value)) return value.slice(0, 200).map((v) => auditable(v, depth + 1));
  if (typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [key, inner] of Object.entries(value as Record<string, unknown>)) {
      out[key] = auditable(inner, depth + 1);
    }
    return out;
  }
  if (typeof value === "number" || typeof value === "boolean" || typeof value === "string") {
    return value;
  }
  return String(value);
}

async function writeAudit(
  actor: Actor,
  action: string,
  targetPath: string,
  before: unknown,
  after: unknown
): Promise<void> {
  await db()
    .collection("adminAudit")
    .add({
      actorUid: actor.uid,
      actorEmail: actor.email,
      action,
      targetPath,
      before: auditable(before),
      after: auditable(after),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  logger.info(`admin action ${action}`, { actorUid: actor.uid, targetPath });
}

async function requireWeek(
  groupId: string,
  weekId: string
): Promise<admin.firestore.DocumentSnapshot> {
  const ref = db().collection("groups").doc(groupId).collection("weeks").doc(weekId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", `Week ${weekId} not found in group ${groupId}.`);
  }
  return snap;
}

/** Grant or revoke the `admin` custom claim on another account. */
export const setAdminRole = onCall(async (request) => {
  const actor = requireSuperAdmin(request);
  const { uid, email, admin: grant } = (request.data ?? {}) as {
    uid?: string;
    email?: string;
    admin?: boolean;
  };
  if (typeof grant !== "boolean") {
    throw new HttpsError("invalid-argument", "`admin` must be a boolean.");
  }

  const user = uid
    ? await admin.auth().getUser(uid)
    : await admin.auth().getUserByEmail(requireString(email, "email"));

  // Revoking your own claim locks you out of this very function.
  if (user.uid === actor.uid && grant === false) {
    throw new HttpsError(
      "failed-precondition",
      "Use another admin account to revoke your own claim."
    );
  }

  const before = user.customClaims?.admin === true;
  await admin.auth().setCustomUserClaims(user.uid, {
    ...(user.customClaims ?? {}),
    admin: grant,
  });
  await writeAudit(actor, "setAdminRole", `auth/users/${user.uid}`, { admin: before }, { admin: grant });

  return {
    uid: user.uid,
    email: user.email ?? null,
    admin: grant,
    // Claims are baked into the ID token: the change is invisible until refresh.
    note: "The user must sign out and back in, or call getIdToken(true), before the claim is live.",
  };
});

/** Force a week status transition and/or set the pick deadline. */
export const adminSetWeekStatus = onCall(async (request) => {
  const actor = requireSuperAdmin(request);
  const data = (request.data ?? {}) as {
    groupId?: string;
    weekId?: string;
    status?: string;
    pickDeadline?: string | null;
  };
  const groupId = requireString(data.groupId, "groupId");
  const weekId = requireString(data.weekId, "weekId");
  const status = requireString(data.status, "status") as WeekStatus;
  if (!WEEK_STATUSES.includes(status)) {
    throw new HttpsError("invalid-argument", `\`status\` must be one of ${WEEK_STATUSES.join(", ")}.`);
  }

  const snap = await requireWeek(groupId, weekId);
  const before = snap.data() ?? {};

  const patch: Record<string, unknown> = { status };
  if (data.pickDeadline !== undefined) {
    if (data.pickDeadline === null) {
      patch.pickDeadline = null;
    } else {
      const parsed = new Date(requireString(data.pickDeadline, "pickDeadline"));
      if (Number.isNaN(parsed.getTime())) {
        throw new HttpsError("invalid-argument", "`pickDeadline` must be an ISO-8601 date string.");
      }
      patch.pickDeadline = admin.firestore.Timestamp.fromDate(parsed);
    }
  }
  if (status === "locked" && before.lockedAt == null) {
    patch.lockedAt = admin.firestore.FieldValue.serverTimestamp();
  }
  // A forced re-open should be able to fire the 24h / 1h reminders again.
  if (status === "picking") {
    patch.deadlineReminder24hSent = false;
    patch.deadlineReminder1hSent = false;
    patch.deadlineReminderSent = false;
  }

  await snap.ref.update(patch);

  // Mirror the onWeekStatusChange trigger for the selection -> picking hop.
  let materialized: unknown = null;
  if (status === "picking" && before.status === "selection") {
    materialized = await materializeNominations(groupId, weekId);
  }

  await writeAudit(
    actor,
    "adminSetWeekStatus",
    snap.ref.path,
    { status: before.status, pickDeadline: before.pickDeadline, lockedAt: before.lockedAt },
    { ...patch, materialized }
  );

  return { groupId, weekId, status, materialized };
});

/** Re-derive a week's `games` from its `nominations`, preserving live scores. */
export const adminRematerializeNominations = onCall(async (request) => {
  const actor = requireSuperAdmin(request);
  const data = (request.data ?? {}) as { groupId?: string; weekId?: string; force?: boolean };
  const groupId = requireString(data.groupId, "groupId");
  const weekId = requireString(data.weekId, "weekId");

  const snap = await requireWeek(groupId, weekId);
  const gamesBefore = await snap.ref.collection("games").get();
  const result = await materializeNominations(groupId, weekId, { force: data.force !== false });

  await writeAudit(
    actor,
    "adminRematerializeNominations",
    `${snap.ref.path}/games`,
    { gameCount: gamesBefore.size },
    result
  );

  return { groupId, weekId, ...result };
});

/** Write or repair a member's pick doc, including the lock flag. */
export const adminUpsertPick = onCall(async (request) => {
  const actor = requireSuperAdmin(request);
  const data = (request.data ?? {}) as {
    groupId?: string;
    weekId?: string;
    userId?: string;
    picks?: Record<string, string>;
    isLocked?: boolean;
    confidenceGameId?: string | null;
  };
  const groupId = requireString(data.groupId, "groupId");
  const weekId = requireString(data.weekId, "weekId");
  const userId = requireString(data.userId, "userId");
  const picks = data.picks ?? {};
  if (typeof picks !== "object" || Array.isArray(picks)) {
    throw new HttpsError("invalid-argument", "`picks` must be a map of gameId -> teamId.");
  }
  for (const [gameId, teamId] of Object.entries(picks)) {
    if (typeof teamId !== "string" || teamId.length === 0) {
      throw new HttpsError("invalid-argument", `Pick for game ${gameId} must be a team id string.`);
    }
  }

  const weekSnap = await requireWeek(groupId, weekId);
  const memberSnap = await db()
    .collection("groups")
    .doc(groupId)
    .collection("members")
    .doc(userId)
    .get();
  const displayName = (memberSnap.data()?.displayName as string | undefined) ?? "Unknown";

  const pickRef = weekSnap.ref.collection("picks").doc(userId);
  const pickSnap = await pickRef.get();
  const before = pickSnap.data() ?? null;
  const isLocked = data.isLocked ?? (before?.isLocked as boolean | undefined) ?? false;

  const payload: Record<string, unknown> = {
    id: userId,
    userId,
    displayName,
    picks,
    isLocked,
    confidenceGameId: data.confidenceGameId ?? before?.confidenceGameId ?? null,
    submittedAt: isLocked
      ? before?.submittedAt ?? admin.firestore.FieldValue.serverTimestamp()
      : null,
  };
  await pickRef.set(payload, { merge: true });

  // Keep the member-visible submission mirror in step with the pick doc.
  await weekSnap.ref.collection("submissions").doc(userId).set(
    {
      id: userId,
      userId,
      displayName,
      isLocked,
      submittedAt: isLocked
        ? before?.submittedAt ?? admin.firestore.FieldValue.serverTimestamp()
        : null,
    },
    { merge: true }
  );

  await writeAudit(actor, "adminUpsertPick", pickRef.path, before, payload);

  return { groupId, weekId, userId, pickCount: Object.keys(picks).length, isLocked };
});

/** Remove a uid from a group and delete every doc that keys off it. */
export const adminRemoveMember = onCall(async (request) => {
  const actor = requireSuperAdmin(request);
  const data = (request.data ?? {}) as { groupId?: string; userId?: string };
  const groupId = requireString(data.groupId, "groupId");
  const userId = requireString(data.userId, "userId");

  const groupRef = db().collection("groups").doc(groupId);
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) {
    throw new HttpsError("not-found", `Group ${groupId} not found.`);
  }
  const group = groupSnap.data() ?? {};
  if (group.commissionerId === userId) {
    throw new HttpsError(
      "failed-precondition",
      "Transfer the commissioner role before removing this member."
    );
  }

  const memberIdsBefore = (group.memberIds as string[] | undefined) ?? [];
  const weeks = await groupRef.collection("weeks").get();

  const batch = db().batch();
  batch.update(groupRef, { memberIds: admin.firestore.FieldValue.arrayRemove(userId) });
  batch.delete(groupRef.collection("members").doc(userId));
  batch.delete(groupRef.collection("career").doc(userId));
  for (const week of weeks.docs) {
    batch.delete(week.ref.collection("picks").doc(userId));
    batch.delete(week.ref.collection("submissions").doc(userId));
  }
  await batch.commit();

  await writeAudit(
    actor,
    "adminRemoveMember",
    groupRef.path,
    { memberIds: memberIdsBefore },
    { removedUserId: userId, weeksCleaned: weeks.size }
  );

  return { groupId, userId, weeksCleaned: weeks.size };
});

/** Hand the commissioner role to another member. */
export const adminTransferCommissioner = onCall(async (request) => {
  const actor = requireSuperAdmin(request);
  const data = (request.data ?? {}) as { groupId?: string; userId?: string };
  const groupId = requireString(data.groupId, "groupId");
  const userId = requireString(data.userId, "userId");

  const groupRef = db().collection("groups").doc(groupId);
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) {
    throw new HttpsError("not-found", `Group ${groupId} not found.`);
  }
  const group = groupSnap.data() ?? {};
  const memberIds = (group.memberIds as string[] | undefined) ?? [];
  if (!memberIds.includes(userId)) {
    throw new HttpsError("failed-precondition", "The new commissioner must already be a member.");
  }
  const previousCommissionerId = (group.commissionerId as string | undefined) ?? null;

  const batch = db().batch();
  batch.update(groupRef, { commissionerId: userId });
  batch.set(groupRef.collection("members").doc(userId), { role: "commissioner" }, { merge: true });
  if (previousCommissionerId && previousCommissionerId !== userId) {
    batch.set(
      groupRef.collection("members").doc(previousCommissionerId),
      { role: "member" },
      { merge: true }
    );
  }
  await batch.commit();

  await writeAudit(
    actor,
    "adminTransferCommissioner",
    groupRef.path,
    { commissionerId: previousCommissionerId },
    { commissionerId: userId }
  );

  return { groupId, commissionerId: userId, previousCommissionerId };
});

interface WeekAuditRow {
  groupId: string;
  groupName: string | null;
  weekId: string;
  expectedWeekId: string | null;
  seasonYear: number | null;
  weekNumber: number | null;
  status: string | null;
  nominationCount: number;
  gameCount: number;
  pickCount: number;
  issues: string[];
}

/**
 * Risk R1 tool: find week docs whose id disagrees with ESPN's numbering, plus
 * duplicate weeks (same season + number) and orphans (no nominations, no
 * games, no picks). Read-only — the portal decides what to merge or delete.
 */
export const adminAuditWeekIds = onCall(async (request) => {
  const actor = requireSuperAdmin(request);
  const data = (request.data ?? {}) as { groupId?: string; seasonYear?: number };
  const seasonYear = typeof data.seasonYear === "number" ? data.seasonYear : null;

  const groupSnaps = data.groupId
    ? [await db().collection("groups").doc(requireString(data.groupId, "groupId")).get()]
    : (await db().collection("groups").get()).docs;

  const rows: WeekAuditRow[] = [];

  for (const groupSnap of groupSnaps) {
    if (!groupSnap.exists) continue;
    const groupName = (groupSnap.data()?.name as string | undefined) ?? null;
    const weeks = await groupSnap.ref.collection("weeks").get();

    // Same season + week number appearing under two doc ids is a split week.
    const seenByNumber = new Map<string, string[]>();
    for (const week of weeks.docs) {
      const w = week.data();
      const year = typeof w.seasonYear === "number" ? w.seasonYear : null;
      const number = typeof w.weekNumber === "number" ? w.weekNumber : null;
      if (year != null && number != null) {
        const key = `${year}-${number}`;
        seenByNumber.set(key, [...(seenByNumber.get(key) ?? []), week.id]);
      }
    }

    for (const week of weeks.docs) {
      const w = week.data();
      const year = typeof w.seasonYear === "number" ? w.seasonYear : null;
      const number = typeof w.weekNumber === "number" ? w.weekNumber : null;
      if (seasonYear != null && year !== seasonYear) continue;

      const expectedWeekId = year != null && number != null ? `${year}-W${number}` : null;
      const [noms, games, picks] = await Promise.all([
        week.ref.collection("nominations").get(),
        week.ref.collection("games").get(),
        week.ref.collection("picks").get(),
      ]);

      const issues: string[] = [];
      if (expectedWeekId == null) issues.push("missingSeasonOrWeekNumber");
      else if (expectedWeekId !== week.id) issues.push("misalignedWeekId");
      if (expectedWeekId != null && (seenByNumber.get(`${year}-${number}`)?.length ?? 0) > 1) {
        issues.push("duplicateWeekNumber");
      }
      if (noms.empty && games.empty && picks.empty) issues.push("orphanWeek");
      if (!games.empty && !noms.empty && games.size !== noms.size) {
        issues.push("gameNominationCountMismatch");
      }
      if (issues.length === 0) continue;

      rows.push({
        groupId: groupSnap.id,
        groupName,
        weekId: week.id,
        expectedWeekId,
        seasonYear: year,
        weekNumber: number,
        status: (w.status as string | undefined) ?? null,
        nominationCount: noms.size,
        gameCount: games.size,
        pickCount: picks.size,
        issues,
      });
    }
  }

  await writeAudit(actor, "adminAuditWeekIds", "groups/*/weeks", null, {
    groupsScanned: groupSnaps.length,
    findings: rows.length,
  });

  return { groupsScanned: groupSnaps.length, rows };
});

/**
 * Recompute a week's results and the affected members' season records.
 *
 * Season totals are re-summed from every scored week rather than incremented,
 * so re-running this is idempotent. `lockAndScoreWeeks` now claims the week
 * inside a transaction and skips if status is already `scored`.
 */
export const adminRescoreWeek = onCall(async (request) => {
  const actor = requireSuperAdmin(request);
  const data = (request.data ?? {}) as { groupId?: string; weekId?: string };
  const groupId = requireString(data.groupId, "groupId");
  const weekId = requireString(data.weekId, "weekId");

  const weekSnap = await requireWeek(groupId, weekId);
  const week = weekSnap.data() ?? {};
  const groupRef = db().collection("groups").doc(groupId);
  const seasonYear = typeof week.seasonYear === "number" ? week.seasonYear : null;

  const [membersSnap, allWeeksSnap, groupSnap] = await Promise.all([
    groupRef.collection("members").get(),
    groupRef.collection("weeks").get(),
    groupRef.get(),
  ]);
  const members = membersSnap.docs.map((d) => ({ id: d.id, ...d.data() } as MemberDoc));
  const rules = (groupSnap.data()?.rules ?? {}) as {
    allowLatePicks?: boolean;
    latePickPenaltyWins?: number;
  };
  const lateOptions = {
    allowLatePicks: rules.allowLatePicks === true,
    latePickPenaltyWins: rules.latePickPenaltyWins,
  };

  // Weeks that count toward the season record: same season, already scored.
  const seasonWeeks = allWeeksSnap.docs.filter((d) => {
    const w = d.data();
    const sameSeason = seasonYear == null || w.seasonYear === seasonYear;
    return sameSeason && (d.id === weekId || w.status === "scored");
  });

  const seasonTotals = new Map<string, { wins: number; losses: number }>();
  let targetGames: SlateGameDoc[] = [];
  let targetPicks: PickDoc[] = [];

  for (const weekDoc of seasonWeeks) {
    const [gamesSnap, picksSnap] = await Promise.all([
      weekDoc.ref.collection("games").get(),
      weekDoc.ref.collection("picks").get(),
    ]);
    const games = gamesSnap.docs.map((d) => ({ id: d.id, ...d.data() } as unknown as SlateGameDoc));
    const picks = picksSnap.docs.map((d) => ({ ...(d.data() as PickDoc), userId: d.id }));
    if (weekDoc.id === weekId) {
      targetGames = games;
      targetPicks = picks;
    }
    for (const pick of picks) {
      const scored = applyLatePickPenalty(scorePicks(pick.picks ?? {}, games, pick.confidenceGameId), {
        ...lateOptions,
        submittedAt: pick.submittedAt,
        deadline: weekDoc.data().pickDeadline,
      });
      const running = seasonTotals.get(pick.userId) ?? { wins: 0, losses: 0 };
      seasonTotals.set(pick.userId, {
        wins: running.wins + scored.wins,
        losses: running.losses + scored.losses,
      });
    }
  }

  const awards = computeWeekAwards(targetPicks, targetGames);
  const batch = db().batch();
  const entries = members.map((member) => {
    const pick = targetPicks.find((p) => p.userId === member.id);
    const scored = applyLatePickPenalty(
      scorePicks(pick?.picks ?? {}, targetGames, pick?.confidenceGameId),
      {
        ...lateOptions,
        submittedAt: pick?.submittedAt,
        deadline: week.pickDeadline,
      }
    );
    const season = seasonTotals.get(member.id) ?? { wins: 0, losses: 0 };
    batch.update(groupRef.collection("members").doc(member.id), {
      seasonWins: season.wins,
      seasonLosses: season.losses,
    });
    return {
      id: member.id,
      displayName: member.displayName,
      avatarColorHex: member.avatarColorHex ?? "#DC2626",
      weeklyWins: scored.wins,
      weeklyLosses: scored.losses,
      seasonWins: season.wins,
      seasonLosses: season.losses,
    };
  });

  const ranked = rankEntries(entries);
  batch.set(groupRef.collection("standings").doc("current"), {
    groupId,
    weekNumber: week.weekNumber ?? null,
    entries: ranked,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  batch.update(weekSnap.ref, {
    status: "scored",
    awards,
    scoredAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();

  await writeAudit(
    actor,
    "adminRescoreWeek",
    weekSnap.ref.path,
    { awards: week.awards ?? null },
    { awards, weeksSummed: seasonWeeks.length, entries: ranked.length }
  );

  return { groupId, weekId, awards, entries: ranked, weeksSummed: seasonWeeks.length };
});
