/** Bowl season week ids — keep in sync with iOS `CFBBowlSeason`. */

import { easternWallTime } from "./cfbWeekWindow";

export const BOWL_SEASON_TYPE = 3;
export const ESPN_POSTSEASON_WEEK = 1;
export const ESPN_BOWL2_POSTSEASON_WEEK = 999;

export const BOWL_SORT_BASE = 900;

export const BOWL_MODE_B_WEEK_ID_SUFFIX = "BOWL";
export const BOWL_CATALOG_SLATE_SOURCE = "bowlCatalog";

export type BowlSlot = "BOWL1" | "BOWL2" | "BOWL";

export type BowlSeasonRules = {
  mode?: "modeA" | "modeB";
  isEnabled?: boolean;
  pickCount?: number;
  countsTowardSeasonStandings?: boolean;
  includesSecondWeek?: boolean;
  suggestedRollingLock?: boolean;
};

/** Keep in sync with iOS `CFBBowlSeason.Settings.default`. Missing `rules.bowlSeason` uses this. */
export const BOWL_SEASON_DEFAULTS: Readonly<
  Required<
    Pick<
      BowlSeasonRules,
      "mode" | "isEnabled" | "countsTowardSeasonStandings" | "includesSecondWeek" | "suggestedRollingLock"
    >
  >
> = {
  mode: "modeA",
  isEnabled: true,
  countsTowardSeasonStandings: false,
  includesSecondWeek: false,
  suggestedRollingLock: true,
};

export function resolveBowlSeasonRules(bowl: BowlSeasonRules | null | undefined): BowlSeasonRules {
  if (bowl == null) return { ...BOWL_SEASON_DEFAULTS };
  return {
    mode: bowl.mode ?? BOWL_SEASON_DEFAULTS.mode,
    isEnabled: bowl.isEnabled ?? BOWL_SEASON_DEFAULTS.isEnabled,
    pickCount: bowl.pickCount,
    countsTowardSeasonStandings:
      bowl.countsTowardSeasonStandings ?? BOWL_SEASON_DEFAULTS.countsTowardSeasonStandings,
    includesSecondWeek: bowl.includesSecondWeek ?? BOWL_SEASON_DEFAULTS.includesSecondWeek,
    suggestedRollingLock: bowl.suggestedRollingLock ?? BOWL_SEASON_DEFAULTS.suggestedRollingLock,
  };
}

export function bowlWeekId(seasonYear: number, slot: BowlSlot): string {
  return `${seasonYear}-${slot}`;
}

export function parseBowlWeekId(weekId: string): { seasonYear: number; slot: BowlSlot } | null {
  const parts = weekId.split("-");
  if (parts.length !== 2) return null;
  const year = Number(parts[0]);
  const slot = parts[1] as BowlSlot;
  if (!Number.isFinite(year)) return null;
  const upper = slot as string;
  if (upper === "BOWL") return { seasonYear: year, slot: "BOWL" };
  if (upper !== "BOWL1" && upper !== "BOWL2") return null;
  return { seasonYear: year, slot: upper as "BOWL1" | "BOWL2" };
}

export function isBowlFullSlateWeek(
  week: { bowlFullSlate?: boolean; slateSource?: string } | undefined,
  weekId?: string
): boolean {
  if (!week) return false;
  if (weekId != null && parseBowlWeekId(weekId)?.slot !== "BOWL") return false;
  if (week.bowlFullSlate === true) return true;
  return week.slateSource === BOWL_CATALOG_SLATE_SOURCE;
}

export function bowlSeasonModeBEnabled(rules: { bowlSeason?: BowlSeasonRules | null } | undefined): boolean {
  const resolved = resolveBowlSeasonRules(rules?.bowlSeason);
  return resolved.isEnabled === true && resolved.mode === "modeB";
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
  if (slot === "BOWL1" || slot === "BOWL") return BOWL_SORT_BASE + 1;
  return BOWL_SORT_BASE + 2;
}

export function bowlSeasonConfigured(rules: { bowlSeason?: BowlSeasonRules | null } | undefined): boolean {
  const resolved = resolveBowlSeasonRules(rules?.bowlSeason);
  return resolved.isEnabled === true && (resolved.mode === "modeA" || resolved.mode === "modeB");
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
/** Every FBS bowl after the selection show, from any ESPN postseason week. */
export function postseasonEventBelongsToCatalog(
  event: { date?: string },
  sourceEspnWeek: number
): boolean {
  const kickoff = eventKickoffMs(event);
  if (kickoff == null) return false;
  if (kickoff < postseasonCatalogOpensMs()) return false;
  return (
    sourceEspnWeek === ESPN_POSTSEASON_WEEK || sourceEspnWeek === ESPN_BOWL2_POSTSEASON_WEEK
  );
}

export function postseasonEventBelongsToBowlSlot(
  event: { date?: string },
  slot: BowlSlot,
  sourceEspnWeek: number
): boolean {
  if (slot === "BOWL") {
    return postseasonEventBelongsToCatalog(event, sourceEspnWeek);
  }
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