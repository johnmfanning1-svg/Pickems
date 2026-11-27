/** Bowl season week ids — keep in sync with iOS `CFBBowlSeason`. */

import { easternWallTime } from "./cfbWeekWindow";

export const BOWL_SEASON_TYPE = 3;
export const ESPN_POSTSEASON_WEEK = 1;
export const ESPN_BOWL2_POSTSEASON_WEEK = 999;

export const BOWL_SORT_BASE = 900;

export type BowlSlot = "BOWL1" | "BOWL2";

export type BowlSeasonRules = {
  mode?: "modeA" | "modeB";
  isEnabled?: boolean;
  pickCount?: number;
  countsTowardSeasonStandings?: boolean;
  includesSecondWeek?: boolean;
  suggestedRollingLock?: boolean;
};

export function bowlWeekId(seasonYear: number, slot: BowlSlot): string {
  return `${seasonYear}-${slot}`;
}

export function parseBowlWeekId(weekId: string): { seasonYear: number; slot: BowlSlot } | null {
  const parts = weekId.split("-");
  if (parts.length !== 2) return null;
  const year = Number(parts[0]);
  const slot = parts[1] as BowlSlot;
  if (!Number.isFinite(year)) return null;
  if (slot !== "BOWL1" && slot !== "BOWL2") return null;
  return { seasonYear: year, slot };
}

export function isBowlWeekId(weekId: string): boolean {
  return parseBowlWeekId(weekId) != null;
}

/** ESPN postseason scoreboard week for bowl week docs — BOWL1→1, BOWL2→999. */
export function espnPostseasonWeekForBowlWeekId(weekId: string): number | null {
  const parsed = parseBowlWeekId(weekId);
  if (!parsed) return null;
  return parsed.slot === "BOWL2" ? ESPN_BOWL2_POSTSEASON_WEEK : ESPN_POSTSEASON_WEEK;
}

export function bowlSortWeekNumber(slot: BowlSlot): number {
  return slot === "BOWL1" ? BOWL_SORT_BASE + 1 : BOWL_SORT_BASE + 2;
}

export function bowlSeasonConfigured(rules: { bowlSeason?: BowlSeasonRules | null } | undefined): boolean {
  const bowl = rules?.bowlSeason;
  return bowl?.isEnabled === true && bowl?.mode === "modeA";
}

export function bowlCountsTowardSeason(rules: { bowlSeason?: BowlSeasonRules | null } | undefined): boolean {
  return rules?.bowlSeason?.countsTowardSeasonStandings === true;
}

/** User-facing bowl week title — keep in sync with iOS `CFBBowlSeason.userFacingBowlWeekName`. */
export const BOWL_USER_FACING_WEEK_NAME = "Bowl Bonanza";

export function userFacingWeekLabel(weekId: string | undefined, weekNumber: unknown): string {
  if (weekId && isBowlWeekId(weekId)) return BOWL_USER_FACING_WEEK_NAME;
  const n =
    typeof weekNumber === "number" && Number.isFinite(weekNumber)
      ? Math.trunc(weekNumber)
      : null;
  if (n == null || n <= 0) return "This week";
  return `Week ${n}`;
}

/** Jan 2 after season year, 00:00 Eastern — BOWL1 catalog ends here (keep in sync with iOS). */
export function bowl1CatalogEndExclusiveMs(seasonYear = 2026): number {
  return easternWallTime(seasonYear + 1, 1, 2, 0, 0, 0, 0).getTime();
}

export function eventKickoffMs(event: { date?: string }): number | null {
  if (!event.date) return null;
  const ms = Date.parse(event.date);
  return Number.isFinite(ms) ? ms : null;
}

export function postseasonCatalogOpensMs(seasonYear = 2026): number {
  // Dec 6 15:00 ET — matches iOS `catalogOpens`.
  return easternWallTime(seasonYear, 12, 6, 15, 0, 0, 0).getTime();
}

/**
 * Partition ESPN postseason events into BOWL1 vs BOWL2 pools without gaps.
 * BOWL1: ESPN week 1 before catalog end. BOWL2: ESPN week 1 on/after end + all week 999.
 */
export function postseasonEventBelongsToBowlSlot(
  event: { date?: string },
  slot: BowlSlot,
  sourceEspnWeek: number
): boolean {
  const kickoff = eventKickoffMs(event);
  if (kickoff == null) return false;
  if (kickoff < postseasonCatalogOpensMs()) return false;
  const cutoff = bowl1CatalogEndExclusiveMs();
  if (sourceEspnWeek === ESPN_BOWL2_POSTSEASON_WEEK) {
    return slot === "BOWL2";
  }
  if (sourceEspnWeek !== ESPN_POSTSEASON_WEEK) return false;
  return slot === "BOWL1" ? kickoff < cutoff : kickoff >= cutoff;
}