import { gameIsLocked, kickoffMillis } from "./pickLock";
import { pickedTeamId, toMillis } from "./scoring";

/**
 * "You took the lead" is not "my rank number is 1".
 *
 * `rankEntries` gives every member of a tie rank 1, and the first member of
 * that tie has `isTied: false`, so rank cannot mean sole leader. An all-zero
 * board is everyone at rank 1. Compare this week's points with this week's
 * previous board, and only after a locked game the user actually picked goes
 * final and adds to their score.
 */
export interface LeadAlertEntry {
  id: string;
  weeklyWins: number;
}

export interface LeadAlertGame {
  id: string;
  status: "scheduled" | "inProgress" | "final";
  kickoff?: unknown;
}

export interface LeadAlertClaimDoc {
  lastWins?: number;
  lastSentAt?: unknown;
  count?: number;
}

export const LEAD_ALERT_COOLDOWN_MS = 30 * 60 * 1000;
export const LEAD_ALERT_MAX_PER_WEEK = 3;

export function tookTheLeadRecipients(input: {
  weekNumber: number;
  week: {
    status?: unknown;
    pickLockMode?: unknown;
    pickDeadline?: unknown;
    remainingLockAt?: unknown;
    gameKickoffs?: Record<string, unknown>;
  };
  /** Freshly ranked live board for THIS week. */
  current: LeadAlertEntry[];
  /** `standings/current` before the write. Missing or another week seeds only. */
  previous: { weekNumber?: unknown; entries?: LeadAlertEntry[] } | undefined;
  /** This pass's games after patching. */
  games: LeadAlertGame[];
  /** Games whose status or score changed THIS pass. */
  changedGameIds: ReadonlySet<string>;
  /** userId -> picks map. */
  picksByUser: Record<string, Record<string, string>>;
  nowMs: number;
}): string[] {
  const { weekNumber, week, current, previous, games, changedGameIds, picksByUser, nowMs } = input;
  if (week.status !== "picking" && week.status !== "locked") return [];
  if (typeof weekNumber !== "number") return [];
  if (previous == null || previous.weekNumber !== weekNumber) return [];

  const previousEntries = Array.isArray(previous.entries) ? previous.entries : [];
  const recipients: string[] = [];
  for (const entry of current) {
    if (typeof entry.weeklyWins !== "number" || !(entry.weeklyWins > 0)) continue;
    if (!strictlyAloneInFirst(current, entry.id, entry.weeklyWins)) continue;
    const prevWins = winsOf(previousEntries, entry.id);
    if (prevWins != null && strictlyAloneInFirst(previousEntries, entry.id, prevWins)) continue;
    if (!(entry.weeklyWins > (prevWins ?? 0))) continue;
    if (!gainedFromLockedFinalPick(entry.id, games, changedGameIds, picksByUser, week, nowMs)) {
      continue;
    }
    recipients.push(entry.id);
  }
  return recipients;
}

/**
 * Skip when this exact score was already alerted, the last send is inside the
 * cooldown, or the user has hit the weekly cap. No existing doc means claim.
 */
export function shouldClaimLeadAlert(
  existing: LeadAlertClaimDoc | null | undefined,
  weeklyWins: number,
  nowMs: number
): boolean {
  if (existing == null) return true;
  if (typeof existing.lastWins === "number" && existing.lastWins >= weeklyWins) return false;
  const sentAt = toMillis(existing.lastSentAt);
  if (sentAt != null && nowMs - sentAt < LEAD_ALERT_COOLDOWN_MS) return false;
  if (typeof existing.count === "number" && existing.count >= LEAD_ALERT_MAX_PER_WEEK) return false;
  return true;
}

/**
 * One game-final push per transition into `final`. A later pass that only
 * refreshes the score, or a retry that already stamped `finalNotifiedAt`,
 * does not send again.
 */
export function shouldNotifyGameFinal(input: {
  prevStatus: unknown;
  nextStatus: unknown;
  finalNotifiedAt?: unknown;
}): boolean {
  if (input.finalNotifiedAt != null) return false;
  return input.prevStatus !== "final" && input.nextStatus === "final";
}

/** Sole leader: points on the board, and strictly more wins than every other entry. */
function strictlyAloneInFirst(
  entries: readonly LeadAlertEntry[],
  userId: string,
  wins: number
): boolean {
  if (!(wins > 0)) return false;
  const others = maxOtherWins(entries, userId);
  return others == null || wins > others;
}

function maxOtherWins(entries: readonly LeadAlertEntry[], userId: string): number | null {
  let max: number | null = null;
  for (const entry of entries) {
    if (entry.id === userId) continue;
    if (typeof entry.weeklyWins !== "number") continue;
    if (max == null || entry.weeklyWins > max) max = entry.weeklyWins;
  }
  return max;
}

function winsOf(entries: readonly LeadAlertEntry[], userId: string): number | null {
  const entry = entries.find((item) => item.id === userId);
  if (!entry || typeof entry.weeklyWins !== "number") return null;
  return entry.weeklyWins;
}

function gainedFromLockedFinalPick(
  userId: string,
  games: readonly LeadAlertGame[],
  changedGameIds: ReadonlySet<string>,
  picksByUser: Record<string, Record<string, string>>,
  week: {
    pickLockMode?: unknown;
    pickDeadline?: unknown;
    remainingLockAt?: unknown;
    gameKickoffs?: Record<string, unknown>;
  },
  nowMs: number
): boolean {
  const picks = picksByUser[userId] ?? {};
  for (const game of games) {
    if (!changedGameIds.has(game.id)) continue;
    if (game.status !== "final") continue;
    if (pickedTeamId(picks, game.id) == null) continue;
    if (!gameIsLocked(week, game.id, game.kickoff, nowMs)) continue;
    const kickoff = kickoffMillis(game.kickoff);
    if (kickoff == null || kickoff > nowMs) continue;
    return true;
  }
  return false;
}
