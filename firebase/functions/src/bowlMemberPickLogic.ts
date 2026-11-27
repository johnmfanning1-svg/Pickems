/** Pure validation for Mode B pick writes — unit-tested. */

import type { GameLockInput, WeekLockInput } from "./spreadLock";
import { gameEffectivelyLocked } from "./spreadLock";

export function validateConfidenceGameId(
  value: unknown,
  slateIds: ReadonlySet<string>,
  explicit: boolean
): string | null {
  if (!explicit) return null;
  if (value === null) return null;
  if (typeof value !== "string") {
    throw new Error("confidenceGameId must be a string or null.");
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new Error("confidenceGameId cannot be empty.");
  }
  if (!slateIds.has(trimmed)) {
    throw new Error(`confidenceGameId ${trimmed} is not on the bowl slate.`);
  }
  return trimmed;
}

export function assertConfidenceChangeAllowed(input: {
  beforeConfidence: unknown;
  afterConfidence: string | null;
  games: Array<GameLockInput & { id: string }>;
  week: WeekLockInput;
  now: number;
}): void {
  const before =
    typeof input.beforeConfidence === "string" && input.beforeConfidence.length > 0
      ? input.beforeConfidence
      : "";
  const after = input.afterConfidence ?? "";
  if (before === after) return;
  if (before.length > 0) {
    const oldGame = input.games.find((g) => g.id === before) ?? { id: before };
    if (gameEffectivelyLocked(input.week, oldGame, input.now)) {
      throw new Error("Cannot change confidence off a game that has started.");
    }
  }
  if (after.length > 0) {
    const newGame = input.games.find((g) => g.id === after) ?? { id: after };
    if (gameEffectivelyLocked(input.week, newGame, input.now)) {
      throw new Error("Cannot set confidence on a game that has started.");
    }
  }
}

export function assertLockTransitionAllowed(beforeLocked: boolean, requestedLocked: boolean | undefined): boolean {
  if (beforeLocked && requestedLocked === false) {
    throw new Error("Submitted picks cannot be unlocked.");
  }
  return requestedLocked === true || (requestedLocked === undefined && beforeLocked);
}