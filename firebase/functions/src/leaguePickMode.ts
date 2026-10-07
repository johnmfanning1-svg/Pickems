import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { isPickMode, resolvePickMode, type PickMode } from "./scoring";

/**
 * Commissioner change of league type (Against the Spread / Straight Up) from
 * the Scoring section of Commissioner Settings.
 *
 * Scoring reads `weeks/{id}.pickMode` first and falls back to
 * `groups/{id}.rules.pickMode` (`resolveWeekPickMode`). One transaction:
 *
 * - `rules.pickMode` = the new mode.
 * - Current week: `pickMode` = new mode when `applyToCurrentWeek` (only while
 *   the week is still in Selections), otherwise pinned to the mode it has now.
 * - Weeks before the current one, and any week whose Pickems opened
 *   (picking / locked / scored): pinned to the old league mode when they have
 *   no stored mode, so a league switch never regrades them. Stored values stay.
 * - Later weeks still in Selections: stored override removed so they follow
 *   the new league mode.
 *
 * Firestore rules only let the commissioner write `pickMode` on selection /
 * picking weeks, so pinning locked and scored weeks has to happen here.
 */

export interface PickModeGroupData {
  commissionerId?: unknown;
  rules?: { pickMode?: unknown } | null;
}

export interface PickModeWeekData {
  status?: unknown;
  pickMode?: unknown;
  seasonYear?: unknown;
  weekNumber?: unknown;
}

export interface PickModeWeek {
  id: string;
  data: PickModeWeekData;
}

export interface LeaguePickModePlan {
  previousMode: PickMode;
  rulesNeedUpdate: boolean;
  /** `null` deletes the week's stored mode so it inherits the league. */
  weekWrites: Array<{ id: string; pickMode: PickMode | null }>;
  /** Current week id when one was found, else null. */
  currentWeekId: string | null;
  currentWeekApplied: boolean;
}

const PICKEMS_STARTED = new Set(["picking", "locked", "scored"]);

/** Sort key for a week; null when the doc has no numeric season/week. */
export function weekOrder(week: PickModeWeekData): number | null {
  const season = typeof week.seasonYear === "number" ? week.seasonYear : null;
  const number = typeof week.weekNumber === "number" ? week.weekNumber : null;
  if (season == null || number == null) return null;
  return season * 1000 + number;
}

/**
 * Pure decision for `setLeaguePickMode`. Throws `HttpsError` for anything the
 * caller may not do; never mutates its inputs.
 */
export function planLeaguePickModeSwitch(input: {
  callerUid: string;
  callerIsAdmin: boolean;
  group: PickModeGroupData | undefined;
  newMode: PickMode;
  applyToCurrentWeek: boolean;
  currentWeekId: string | null;
  weeks: PickModeWeek[];
}): LeaguePickModePlan {
  const { callerUid, callerIsAdmin, group, newMode, applyToCurrentWeek, currentWeekId, weeks } = input;
  if (!group) {
    throw new HttpsError("not-found", "League not found.");
  }
  if (!callerIsAdmin && group.commissionerId !== callerUid) {
    throw new HttpsError("permission-denied", "Only the commissioner can change the league type.");
  }

  const previousMode = resolvePickMode(group.rules?.pickMode);
  const current = currentWeekId ? weeks.find((week) => week.id === currentWeekId) ?? null : null;

  if (applyToCurrentWeek && current && current.data.status !== "selection") {
    throw new HttpsError(
      "failed-precondition",
      "Pickems are already open for this week, so the change can only start next week."
    );
  }

  const currentOrder = current ? weekOrder(current.data) : null;
  const weekWrites: Array<{ id: string; pickMode: PickMode | null }> = [];

  for (const week of weeks) {
    const stored = isPickMode(week.data.pickMode) ? week.data.pickMode : null;

    if (current && week.id === current.id) {
      const target: PickMode = applyToCurrentWeek ? newMode : stored ?? previousMode;
      if (stored !== target) weekWrites.push({ id: week.id, pickMode: target });
      continue;
    }

    const order = weekOrder(week.data);
    const isEarlier = currentOrder != null && order != null && order < currentOrder;
    const pickemsStarted = typeof week.data.status === "string" && PICKEMS_STARTED.has(week.data.status);
    if (isEarlier || pickemsStarted) {
      if (stored == null) weekWrites.push({ id: week.id, pickMode: previousMode });
      continue;
    }

    // Later week still in Selections (or not opened): follow the new league mode.
    if (stored != null) weekWrites.push({ id: week.id, pickMode: null });
  }

  return {
    previousMode,
    rulesNeedUpdate: resolvePickMode(group.rules?.pickMode) !== newMode || !isPickMode(group.rules?.pickMode),
    weekWrites,
    currentWeekId: current?.id ?? null,
    // An unminted current week inherits the new league mode when it is created.
    currentWeekApplied: applyToCurrentWeek,
  };
}

function optionalString(value: unknown, field: string): string | null {
  if (value == null) return null;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `\`${field}\` must be a non-empty string.`);
  }
  return value.trim();
}

export const setLeaguePickMode = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const data = (request.data ?? {}) as {
    groupId?: unknown;
    pickMode?: unknown;
    applyToCurrentWeek?: unknown;
    weekId?: unknown;
  };
  const groupId = optionalString(data.groupId, "groupId");
  if (!groupId) {
    throw new HttpsError("invalid-argument", "`groupId` is required.");
  }
  if (!isPickMode(data.pickMode)) {
    throw new HttpsError("invalid-argument", "`pickMode` must be \"ats\" or \"straightUp\".");
  }
  if (typeof data.applyToCurrentWeek !== "boolean") {
    throw new HttpsError("invalid-argument", "`applyToCurrentWeek` must be a boolean.");
  }
  const newMode = data.pickMode;
  const applyToCurrentWeek = data.applyToCurrentWeek;
  const currentWeekId = optionalString(data.weekId, "weekId");
  const callerIsAdmin = auth.token.admin === true;

  const db = getFirestore();
  const groupRef = db.collection("groups").doc(groupId);
  const weeksRef = groupRef.collection("weeks");

  const result = await db.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    const weeksSnap = await tx.get(weeksRef);
    const plan = planLeaguePickModeSwitch({
      callerUid: auth.uid,
      callerIsAdmin,
      group: groupSnap.exists ? (groupSnap.data() as PickModeGroupData) : undefined,
      newMode,
      applyToCurrentWeek,
      currentWeekId,
      weeks: weeksSnap.docs.map((doc) => ({ id: doc.id, data: doc.data() as PickModeWeekData })),
    });

    if (plan.rulesNeedUpdate) {
      tx.update(groupRef, { "rules.pickMode": newMode });
    }
    for (const write of plan.weekWrites) {
      tx.update(weeksRef.doc(write.id), {
        pickMode: write.pickMode ?? FieldValue.delete(),
      });
    }

    const weekModes: Record<string, PickMode | null> = {};
    for (const write of plan.weekWrites) weekModes[write.id] = write.pickMode;
    return {
      groupId,
      pickMode: newMode,
      previousMode: plan.previousMode,
      rulesChanged: plan.rulesNeedUpdate,
      currentWeekId: plan.currentWeekId,
      currentWeekApplied: plan.currentWeekApplied,
      weekModes,
    };
  });

  logger.info("setLeaguePickMode", {
    callerUid: auth.uid,
    callerIsAdmin,
    groupId: result.groupId,
    pickMode: result.pickMode,
    previousMode: result.previousMode,
    currentWeekId: result.currentWeekId,
    currentWeekApplied: result.currentWeekApplied,
    weekWrites: Object.keys(result.weekModes).length,
  });
  return result;
});
