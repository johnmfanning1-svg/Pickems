import { kickoffMillis } from "./pickLock";
import { MAX_PUSH_BODY_LENGTH, MAX_PUSH_TITLE_LENGTH } from "./pushCopy";
import { leagueDisplayName, teamTag } from "./pushAlert";

/** Stored on `groups/{id}.rules`. Missing means off. */
export const VETO_ENABLED_FIELD = "vetoEnabled";
/** Stored on `groups/{id}.rules`. Missing means {@link DEFAULT_VETO_VOTES_NEEDED}. */
export const VETO_VOTES_NEEDED_FIELD = "vetoVotesNeeded";
export const DEFAULT_VETO_VOTES_NEEDED = 2;

export const SELECTION_VETO_PUSH_TYPE = "selection_veto";
export const SELECTION_VETO_SELECTOR_TITLE = "Your Selection was vetoed";
export const SELECTION_VETO_LEAGUE_TITLE = "Selection vetoed";

export interface VetoRulesFields {
  vetoEnabled?: unknown;
  vetoVotesNeeded?: unknown;
  selectionMode?: unknown;
}

export interface VetoGroupFields {
  name?: unknown;
  memberIds?: unknown;
  rules?: VetoRulesFields | null;
}

/**
 * True when a group write might make an in-progress Selection reach the
 * veto threshold: the feature was just turned on, the number of votes
 * required went down, or the roster shrank (which lowers the cap).
 */
export function vetoSettingsMayApply(before: VetoGroupFields, after: VetoGroupFields): boolean {
  if (after.rules?.vetoEnabled !== true) return false;
  if (before.rules?.vetoEnabled !== true) return true;

  const beforeNeeded = finiteInt(before.rules?.vetoVotesNeeded);
  const afterNeeded = finiteInt(after.rules?.vetoVotesNeeded);
  if (afterNeeded != null && (beforeNeeded == null || afterNeeded < beforeNeeded)) return true;

  const beforeMembers = memberIdList(before.memberIds).length;
  const afterMembers = memberIdList(after.memberIds).length;
  return afterMembers < beforeMembers;
}

export function memberIdList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const ids: string[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") continue;
    const id = entry.trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }
  return ids;
}

/**
 * Votes required to remove a Selection.
 * Null when nobody else can vote (a one-person league).
 * Otherwise clamped to 1…(league size − 1). A missing or unusable number
 * falls back to {@link DEFAULT_VETO_VOTES_NEEDED} before the clamp.
 */
export function effectiveVetoVotesNeeded(configured: unknown, memberCount: number): number | null {
  const others = Math.floor(memberCount) - 1;
  if (!Number.isFinite(others) || others < 1) return null;
  const raw = finiteInt(configured);
  const chosen = raw != null && raw >= 1 ? raw : DEFAULT_VETO_VOTES_NEEDED;
  return Math.min(chosen, others);
}

/** Doc id for `weeks/{weekId}/vetoes/{id}`. One record per selector and game. */
export function selectionVetoRecordId(selectorId: string, espnEventId: string): string {
  return `${selectorId}_${espnEventId}`;
}

/**
 * Several members can be vetoed off the same ESPN event. A retry after the
 * Selection is gone must finish the record that has not been announced yet.
 * Returns -1 when there is nothing to read.
 */
export function indexOfPendingVetoRecord(
  records: ReadonlyArray<{ notified?: unknown }>
): number {
  const pending = records.findIndex((record) => record.notified !== true);
  if (pending >= 0) return pending;
  return records.length > 0 ? 0 : -1;
}

export function isMemberSelectionWeek(weekMode: unknown, groupMode: unknown): boolean {
  if (weekMode === "commissioner" || groupMode === "commissioner") return false;
  if (weekMode === "member" || groupMode === "member") return true;
  return weekMode == null && groupMode == null;
}

/**
 * Selections are still open and this game has not kicked off.
 * A missing kickoff is closed: the vote cannot prove the game is still ahead.
 * Equality is closed, matching the security rules (`request.time < deadline`).
 */
export function selectionVetoWindowOpen(input: {
  nowMs: number;
  weekStatus: unknown;
  weekSelectionMode: unknown;
  groupSelectionMode: unknown;
  selectionDeadlineMs: number | null;
  kickoffMs: number | null;
}): boolean {
  if (input.weekStatus !== "selection") return false;
  if (!isMemberSelectionWeek(input.weekSelectionMode, input.groupSelectionMode)) return false;
  if (input.selectionDeadlineMs != null && input.nowMs >= input.selectionDeadlineMs) return false;
  if (input.kickoffMs == null || input.nowMs >= input.kickoffMs) return false;
  return true;
}

/** Current members other than the selector. Each id counts once. */
export function eligibleVetoVoterIds(
  voterIds: readonly string[],
  memberIds: readonly string[],
  selectorId: string
): string[] {
  const members = new Set(memberIds);
  const seen = new Set<string>();
  const eligible: string[] = [];
  for (const id of voterIds) {
    if (!id || id === selectorId || !members.has(id) || seen.has(id)) continue;
    seen.add(id);
    eligible.push(id);
  }
  return eligible;
}

export type SelectionVetoPlan =
  | { kind: "skip" }
  | { kind: "drop_trigger_vote" }
  | { kind: "tally"; count: number; votesNeeded: number }
  | { kind: "apply"; count: number; votesNeeded: number }
  | { kind: "notify_only" };

export function planSelectionVeto(input: {
  nowMs: number;
  vetoEnabled: boolean;
  configuredVotesNeeded: unknown;
  memberIds: readonly string[];
  weekStatus: unknown;
  weekSelectionMode: unknown;
  groupSelectionMode: unknown;
  selectionDeadlineMs: number | null;
  kickoffMs: number | null;
  selectorId: string;
  voterIds: readonly string[];
  triggerVoterId: string | null;
  nominationExists: boolean;
  vetoRecorded: boolean;
  vetoNotified: boolean;
}): SelectionVetoPlan {
  if (!input.nominationExists) {
    if (input.vetoRecorded && !input.vetoNotified) return { kind: "notify_only" };
    return { kind: "skip" };
  }

  if (!input.selectorId.trim()) {
    if (input.triggerVoterId) return { kind: "drop_trigger_vote" };
    return { kind: "skip" };
  }

  const eligible = eligibleVetoVoterIds(input.voterIds, input.memberIds, input.selectorId);
  const triggerIneligible =
    input.triggerVoterId != null && !eligible.includes(input.triggerVoterId);
  const windowOpen = selectionVetoWindowOpen({
    nowMs: input.nowMs,
    weekStatus: input.weekStatus,
    weekSelectionMode: input.weekSelectionMode,
    groupSelectionMode: input.groupSelectionMode,
    selectionDeadlineMs: input.selectionDeadlineMs,
    kickoffMs: input.kickoffMs,
  });

  if (!input.vetoEnabled || !windowOpen) {
    if (input.triggerVoterId != null && (triggerIneligible || !input.vetoEnabled)) {
      return { kind: "drop_trigger_vote" };
    }
    return { kind: "skip" };
  }

  const votesNeeded = effectiveVetoVotesNeeded(input.configuredVotesNeeded, input.memberIds.length);
  if (votesNeeded == null) {
    if (input.triggerVoterId != null) return { kind: "drop_trigger_vote" };
    return { kind: "skip" };
  }

  if (eligible.length >= votesNeeded) {
    return { kind: "apply", count: eligible.length, votesNeeded };
  }
  if (triggerIneligible) return { kind: "drop_trigger_vote" };
  return { kind: "tally", count: eligible.length, votesNeeded };
}

export function selectionMatchupLabel(input: {
  awayTeamAbbreviation?: unknown;
  awayTeamName?: unknown;
  homeTeamAbbreviation?: unknown;
  homeTeamName?: unknown;
}): string {
  const away = teamTag(input.awayTeamAbbreviation, input.awayTeamName, "AWAY");
  const home = teamTag(input.homeTeamAbbreviation, input.homeTeamName, "HOME");
  return `${away} @ ${home}`;
}

export interface SelectionVetoMessage {
  title: string;
  body: string;
}

export interface SelectionVetoMessages {
  selector: SelectionVetoMessage;
  league: SelectionVetoMessage;
}

/**
 * Selector copy is distinct from the rest of the league.
 * Both name the game and the league. Bodies stay within the push limit.
 */
export function selectionVetoMessages(gameLabel: string, leagueName: unknown): SelectionVetoMessages {
  const game = clip(gameLabel, 40) || "This game";
  const league = clip(leagueDisplayName(leagueName), 40);
  return {
    selector: {
      title: SELECTION_VETO_SELECTOR_TITLE,
      body: fitBody(`${game} was vetoed in ${league}. Your slot is open — pick a different game.`),
    },
    league: {
      title: SELECTION_VETO_LEAGUE_TITLE,
      body: fitBody(`${game} was vetoed in ${league}.`),
    },
  };
}

export function selectionVetoTitlesFit(): boolean {
  const selector: string = SELECTION_VETO_SELECTOR_TITLE;
  const league: string = SELECTION_VETO_LEAGUE_TITLE;
  return (
    selector.length <= MAX_PUSH_TITLE_LENGTH &&
    league.length <= MAX_PUSH_TITLE_LENGTH &&
    selector !== league
  );
}

/** Slate docs for this ESPN event (doc id or `espnEventId`). */
export function slateGameIdsForEvent(
  games: ReadonlyArray<{ id: string; espnEventId?: unknown }>,
  espnEventId: string,
  remainingNominationEventIds: readonly string[] = []
): string[] {
  if (remainingNominationEventIds.includes(espnEventId)) return [];
  const ids = new Set<string>();
  for (const game of games) {
    if (game.id === espnEventId || game.espnEventId === espnEventId) ids.add(game.id);
  }
  return [...ids];
}

/** ESPN event ids still selected after this nomination doc is removed. */
export function nominationEventIdsAfterRemoval(
  nominations: ReadonlyArray<{ id: string; espnEventId?: unknown }>,
  removedId: string
): string[] {
  const ids: string[] = [];
  for (const nomination of nominations) {
    if (nomination.id === removedId) continue;
    const raw = nomination.espnEventId;
    const eventId = typeof raw === "string" && raw.trim() ? raw.trim() : nomination.id;
    ids.push(eventId);
  }
  return ids;
}

/** Nomination counter after this Selection is removed. */
export function nominationCountAfterRemoval(existingIds: readonly string[], removedId: string): number {
  return existingIds.filter((id) => id !== removedId).length;
}

export function deadlineMillis(value: unknown): number | null {
  return kickoffMillis(value);
}

/** True when every recipient send that should count has succeeded. */
export function selectionVetoDeliverySucceeded(results: readonly boolean[]): boolean {
  return results.length > 0 && results.every((ok) => ok === true);
}

export const SELECTION_VETO_VOTE_TRIGGER = {
  document: "groups/{groupId}/weeks/{weekId}/nominations/{nominationId}/vetoVotes/{voterId}",
  retry: true,
} as const;

export const SELECTION_VETO_SETTINGS_TRIGGER = {
  document: "groups/{groupId}",
  retry: true,
} as const;

function finiteInt(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.floor(value);
}

function clip(value: string, max: number): string {
  const clean = value.replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  return clean.slice(0, max).trimEnd();
}

function fitBody(value: string): string {
  return clip(value, MAX_PUSH_BODY_LENGTH);
}
