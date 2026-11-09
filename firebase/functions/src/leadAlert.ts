import { gameIsLocked, isRollingLock, kickoffMillis } from "./pickLock";
import { toMillis } from "./scoring";

/**
 * "You took the lead" is not "my rank number is 1".
 *
 * `rankEntries` gives every member of a tie rank 1, and the first member of
 * that tie has `isTied: false`, so rank cannot mean sole leader. An all-zero
 * board is everyone at rank 1. Compare this week's points with this week's
 * previous board. A locked game that goes final can hand someone the lead
 * when a rival drops, even if the new leader's own score did not move.
 *
 * On a rolling-lock week the first final can also crown whoever picked that
 * one game, because everyone else is an automatic miss. Wait until at least
 * half the roster has a pick before sending that push.
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
  /**
   * Roster ids with at least one team on this week's pick doc.
   * `refreshLiveStandings` always passes this, including an empty set when
   * nobody has picked. Omit it only in a fixture that is not exercising
   * this guard.
   */
  pickedUserIds?: ReadonlySet<string>;
  nowMs: number;
}): string[] {
  const { weekNumber, week, current, previous, games, changedGameIds, pickedUserIds, nowMs } =
    input;
  if (week.status !== "picking" && week.status !== "locked") return [];
  if (typeof weekNumber !== "number") return [];
  if (previous == null || previous.weekNumber !== weekNumber) return [];
  if (!lockedFinalThisPass(games, changedGameIds, week, nowMs)) return [];

  const previousEntries = Array.isArray(previous.entries) ? previous.entries : [];
  if (!boardChanged(current, previousEntries)) return [];
  if (pickedUserIds != null && rollingRosterMostlyUnpicked(week, current, pickedUserIds)) {
    return [];
  }

  const recipients: string[] = [];
  for (const entry of current) {
    if (typeof entry.weeklyWins !== "number" || !(entry.weeklyWins > 0)) continue;
    if (!strictlyAloneInFirst(current, entry.id, entry.weeklyWins)) continue;
    const prevWins = winsOf(previousEntries, entry.id);
    if (prevWins != null && strictlyAloneInFirst(previousEntries, entry.id, prevWins)) continue;
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

/**
 * User ids whose pick doc has at least one team. A saved draft counts — those
 * picks are on the board. A blank doc does not.
 */
export function userIdsWithPicks(
  pickDocs: ReadonlyArray<{ userId?: unknown; picks?: unknown }>
): Set<string> {
  const ids = new Set<string>();
  for (const doc of pickDocs) {
    if (typeof doc.userId !== "string" || doc.userId.length === 0) continue;
    if (!pickMapHasTeam(doc.picks)) continue;
    ids.add(doc.userId);
  }
  return ids;
}

/**
 * Rolling lock scores a missed Pickem as a loss at kickoff. One correct
 * Thursday pick is then strictly alone at 1–0 while most of the league has
 * not picked. That push waits until pick docs are at least half the roster.
 * Exactly half is enough, so a Thursday lead still notifies once the league
 * has actually started picking. Deadline-lock weeks are unchanged.
 */
function rollingRosterMostlyUnpicked(
  week: { pickLockMode?: unknown },
  current: readonly LeadAlertEntry[],
  pickedUserIds: ReadonlySet<string>
): boolean {
  if (!isRollingLock(week.pickLockMode)) return false;
  const roster = new Set<string>();
  for (const entry of current) {
    if (entry.id.length > 0) roster.add(entry.id);
  }
  if (roster.size === 0) return false;
  let picked = 0;
  for (const id of roster) {
    if (pickedUserIds.has(id)) picked += 1;
  }
  return picked * 2 < roster.size;
}

function pickMapHasTeam(picks: unknown): boolean {
  if (picks == null || typeof picks !== "object") return false;
  for (const value of Object.values(picks as Record<string, unknown>)) {
    if (typeof value === "string" && value.trim().length > 0) return true;
  }
  return false;
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

/** A locked game with a past kickoff moved to final in this pass. */
function lockedFinalThisPass(
  games: readonly LeadAlertGame[],
  changedGameIds: ReadonlySet<string>,
  week: {
    pickLockMode?: unknown;
    pickDeadline?: unknown;
    remainingLockAt?: unknown;
    gameKickoffs?: Record<string, unknown>;
  },
  nowMs: number
): boolean {
  for (const game of games) {
    if (!changedGameIds.has(game.id)) continue;
    if (game.status !== "final") continue;
    if (!gameIsLocked(week, game.id, game.kickoff, nowMs)) continue;
    const kickoff = kickoffMillis(game.kickoff);
    if (kickoff == null || kickoff > nowMs) continue;
    return true;
  }
  return false;
}

/** Win totals moved versus this week's previous board, including a rival dropping. */
function boardChanged(
  current: readonly LeadAlertEntry[],
  previous: readonly LeadAlertEntry[]
): boolean {
  if (current.length !== previous.length) return true;
  const previousWins = new Map<string, number>();
  for (const entry of previous) {
    if (typeof entry.weeklyWins === "number") previousWins.set(entry.id, entry.weeklyWins);
  }
  if (previousWins.size !== previous.length) return true;
  for (const entry of current) {
    if (!previousWins.has(entry.id)) return true;
    if (previousWins.get(entry.id) !== entry.weeklyWins) return true;
  }
  return false;
}
