import { toDate } from "./format";
import type { DeadlinePolicy, WeekStatus } from "./types";

/**
 * Mirrors `gameEffectivelyLocked` in `firebase/functions/src/spreadLock.ts`.
 * A week unlock reopens only games that are still pregame and before kickoff.
 */
export interface WeekLockInput {
  status?: WeekStatus | null;
  pickLockMode?: DeadlinePolicy | null;
  pickDeadline?: unknown;
  weekLockAt?: unknown;
  remainingLockAt?: unknown;
  allowLatePicks?: boolean;
}

export interface GameLockInput {
  kickoff?: unknown;
  status?: string | null;
}

function millis(value: unknown): number | null {
  const date = toDate(value);
  return date ? date.getTime() : null;
}

export function canonicalPhase(status: unknown): "pre" | "in" | "post" {
  if (status === "in" || status === "inProgress") return "in";
  if (status === "post" || status === "final") return "post";
  return "pre";
}

export function isPregameStatus(status: unknown): boolean {
  if (status == null || status === "") return true;
  return canonicalPhase(status) === "pre";
}

export function weekLevelLocked(week: WeekLockInput, now = Date.now()): boolean {
  if (week.status === "locked" || week.status === "scored") return true;
  if (week.status === "selection") return false;
  const remaining = millis(week.remainingLockAt);
  if (remaining != null && now >= remaining) return true;
  if (week.pickLockMode === "rolling") {
    const weekLock = millis(week.weekLockAt);
    return weekLock != null && now >= weekLock;
  }
  if (week.allowLatePicks === true) return false;
  const deadline = millis(week.pickDeadline);
  return deadline != null && now >= deadline;
}

export function gameEffectivelyLocked(
  week: WeekLockInput,
  game: GameLockInput,
  now = Date.now(),
): boolean {
  if (weekLevelLocked(week, now)) return true;
  if (!isPregameStatus(game.status)) return true;
  const kick = millis(game.kickoff);
  return kick != null && now >= kick;
}
