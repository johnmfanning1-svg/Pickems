/** Bowl season week ids — keep in sync with iOS `CFBBowlSeason`. */

export const BOWL_SEASON_TYPE = 3;
export const ESPN_POSTSEASON_WEEK = 1;

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