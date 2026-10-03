import {
  FieldValue,
  Timestamp,
  getFirestore,
  type DocumentReference,
  type DocumentSnapshot,
} from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { isRollingLock, kickoffMillis } from "./pickLock";

/**
 * Commissioner switch to rolling pick lock, optionally applied to the week in
 * progress. Mirrors the hand repair done for Core 4 OG 2026-W5 on 2026-10-02:
 *
 * - `groups/{id}.rules.pickDeadline` = "rolling" (every call).
 * - With `applyToCurrentWeek`, one atomic week update: `pickLockMode`
 *   "rolling", `weekLockAt` = latest `gameKickoffs` value, `status` "picking",
 *   `lockedAt` deleted. Nothing else on the week changes. Picks, standings and
 *   games are never touched.
 *
 * Started games stay locked: the rolling Firestore rules deny pick and
 * confidence changes once a game's stamped kickoff has passed, and
 * `lockAndScoreWeeks` reveals those games' picks and relocks the week only at
 * `weekLockAt`.
 */

export interface RollingGroupData {
  commissionerId?: unknown;
  rules?: { pickDeadline?: unknown } | null;
}

export interface RollingWeekData {
  status?: unknown;
  pickLockMode?: unknown;
  weekLockAt?: unknown;
  lockedAt?: unknown;
  gameKickoffs?: Record<string, unknown> | null;
}

/** Latest stamped kickoff on the week, or null when none can be read. */
export function latestStampedKickoffMillis(week: RollingWeekData): number | null {
  const values = Object.values(week.gameKickoffs ?? {});
  const times = values
    .map((value) => kickoffMillis(value))
    .filter((ms): ms is number => ms != null);
  return times.length ? Math.max(...times) : null;
}

/** Earliest stamped kickoff on the week, or null when none can be read. */
export function earliestStampedKickoffMillis(week: RollingWeekData): number | null {
  const values = Object.values(week.gameKickoffs ?? {});
  const times = values
    .map((value) => kickoffMillis(value))
    .filter((ms): ms is number => ms != null);
  return times.length ? Math.min(...times) : null;
}

/**
 * A week is in progress when it is picking or locked, not scored, and either
 * locked or past its first kickoff. Same definition as the iOS
 * `RollingLockSwitch.currentWeekPhase`.
 */
export function weekInProgress(week: RollingWeekData, nowMs: number): boolean {
  if (week.status === "locked") return true;
  if (week.status !== "picking") return false;
  const first = earliestStampedKickoffMillis(week);
  return first != null && first <= nowMs;
}

export interface RollingSwitchPlan {
  /** True when `rules.pickDeadline` is not already "rolling". */
  rulesNeedUpdate: boolean;
  /** Null when the caller did not ask to apply it to a week. */
  week:
    | null
    | {
        /** False when the week is already on rolling lock (idempotent retry). */
        needsUpdate: boolean;
        weekLockAtMs: number | null;
      };
}

/**
 * Pure decision for `setRollingLock`. Throws `HttpsError` for anything the
 * caller should not be allowed to do; never mutates its inputs.
 */
export function planRollingSwitch(input: {
  nowMs: number;
  callerUid: string;
  callerIsAdmin: boolean;
  group: RollingGroupData | undefined;
  applyToCurrentWeek: boolean;
  week?: RollingWeekData;
}): RollingSwitchPlan {
  const { nowMs, callerUid, callerIsAdmin, group, applyToCurrentWeek, week } = input;
  if (!group) {
    throw new HttpsError("not-found", "League not found.");
  }
  if (!callerIsAdmin && group.commissionerId !== callerUid) {
    throw new HttpsError("permission-denied", "Only the commissioner can change the pick lock.");
  }

  const rulesNeedUpdate = !isRollingLock(group.rules?.pickDeadline);
  if (!applyToCurrentWeek) {
    return { rulesNeedUpdate, week: null };
  }

  if (!week) {
    throw new HttpsError("not-found", "That week was not found.");
  }
  if (week.status === "scored") {
    throw new HttpsError("failed-precondition", "That week is already final.");
  }
  if (isRollingLock(week.pickLockMode)) {
    // Already applied (retry, or the week opened on rolling). Leave the week
    // exactly as it is so a commissioner "lock remaining now" is not undone.
    return { rulesNeedUpdate, week: { needsUpdate: false, weekLockAtMs: null } };
  }
  if (week.status !== "picking" && week.status !== "locked") {
    throw new HttpsError("failed-precondition", "That week has not opened for Pickems yet.");
  }

  const latest = latestStampedKickoffMillis(week);
  if (latest == null) {
    throw new HttpsError(
      "failed-precondition",
      "That week has no kickoff times yet, so rolling lock can't be applied to it."
    );
  }
  if (latest <= nowMs) {
    throw new HttpsError(
      "failed-precondition",
      "Every game this week has already kicked off. Rolling lock will start next week."
    );
  }
  return { rulesNeedUpdate, week: { needsUpdate: true, weekLockAtMs: latest } };
}

/** The single week write. Exported for tests; keys match the Core 4 OG repair. */
export function rollingWeekUpdate(weekLockAtMs: number): Record<string, unknown> {
  return {
    pickLockMode: "rolling",
    weekLockAt: Timestamp.fromMillis(weekLockAtMs),
    status: "picking",
    lockedAt: FieldValue.delete(),
  };
}

function optionalString(value: unknown, field: string): string | null {
  if (value == null) return null;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `\`${field}\` must be a non-empty string.`);
  }
  return value.trim();
}

export const setRollingLock = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const data = (request.data ?? {}) as {
    groupId?: unknown;
    applyToCurrentWeek?: unknown;
    weekId?: unknown;
  };
  const groupId = optionalString(data.groupId, "groupId");
  if (!groupId) {
    throw new HttpsError("invalid-argument", "`groupId` is required.");
  }
  if (typeof data.applyToCurrentWeek !== "boolean") {
    throw new HttpsError("invalid-argument", "`applyToCurrentWeek` must be a boolean.");
  }
  const applyToCurrentWeek = data.applyToCurrentWeek;
  const requestedWeekId = optionalString(data.weekId, "weekId");
  const callerIsAdmin = auth.token.admin === true;

  const db = getFirestore();
  const groupRef = db.collection("groups").doc(groupId);

  const result = await db.runTransaction(async (tx) => {
    const nowMs = Date.now();
    const groupSnap = await tx.get(groupRef);
    const group = groupSnap.exists ? (groupSnap.data() as RollingGroupData) : undefined;

    let weekRef: DocumentReference | null = null;
    let weekSnap: DocumentSnapshot | null = null;
    if (applyToCurrentWeek && group) {
      if (requestedWeekId) {
        weekRef = groupRef.collection("weeks").doc(requestedWeekId);
        weekSnap = await tx.get(weekRef);
      } else {
        const open = await tx.get(
          groupRef.collection("weeks").where("status", "in", ["picking", "locked"])
        );
        const inProgress = open.docs.filter((doc) =>
          weekInProgress(doc.data() as RollingWeekData, nowMs)
        );
        if (inProgress.length === 0) {
          throw new HttpsError("failed-precondition", "No week is in progress.");
        }
        if (inProgress.length > 1) {
          throw new HttpsError(
            "failed-precondition",
            "More than one week is in progress. Pass `weekId`."
          );
        }
        weekSnap = inProgress[0];
        weekRef = weekSnap.ref;
      }
    }

    const plan = planRollingSwitch({
      nowMs,
      callerUid: auth.uid,
      callerIsAdmin,
      group,
      applyToCurrentWeek,
      week: weekSnap?.exists ? (weekSnap.data() as RollingWeekData) : undefined,
    });

    if (plan.rulesNeedUpdate) {
      tx.update(groupRef, { "rules.pickDeadline": "rolling" });
    }
    const weekChanged = !!(plan.week?.needsUpdate && weekRef && plan.week.weekLockAtMs != null);
    if (weekChanged && weekRef && plan.week?.weekLockAtMs != null) {
      tx.update(weekRef, rollingWeekUpdate(plan.week.weekLockAtMs));
    }
    return {
      groupId,
      weekId: weekRef?.id ?? null,
      rulesChanged: plan.rulesNeedUpdate,
      weekChanged,
      weekLockAt:
        weekChanged && plan.week?.weekLockAtMs != null
          ? new Date(plan.week.weekLockAtMs).toISOString()
          : null,
    };
  });

  logger.info("setRollingLock", { callerUid: auth.uid, callerIsAdmin, ...result });
  return result;
});
