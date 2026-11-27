/** Shared season-close rules for `autoCloseSeasons` (tested here, wired in `index.ts`). */

export const POSTSEASON_SEASON_TYPE = 3;

/** ESPN postseason week 1 must not map onto regular-season `2026-W1`. */
export function espnPostseasonWouldMintRegularWeekOne(seasonYear: number, espnWeekNumber: number, seasonType: number): boolean {
  return seasonYear === 2026 && seasonType === POSTSEASON_SEASON_TYPE && espnWeekNumber === 1;
}

export function isBowlWeekDocumentId(weekId: string): boolean {
  return /^\d{4}-BOWL\d*$/i.test(weekId);
}

/** Bowl weeks still in play block the annual archive until they are scored. */
export function isOpenBowlWeek(weekId: string, week: { status?: unknown; seasonType?: unknown }): boolean {
  if (!isBowlWeekDocumentId(weekId)) return false;
  if (week.seasonType === POSTSEASON_SEASON_TYPE) {
    return week.status !== "scored";
  }
  return week.status === "selection" || week.status === "picking" || week.status === "locked";
}

export function groupShouldSkipAutoClose(
  weeks: Array<{ id: string; data: { status?: unknown; seasonType?: unknown } }>
): boolean {
  return weeks.some((w) => isOpenBowlWeek(w.id, w.data));
}

/** Scheduled run is Feb 1 Eastern — archive the CFB season year that ended the prior January. */
export function seasonYearToArchive(runAt: Date, timeZone = "America/New_York"): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "numeric",
  }).formatToParts(runAt);
  const year = Number(parts.find((p) => p.type === "year")?.value ?? "0");
  const month = Number(parts.find((p) => p.type === "month")?.value ?? "0");
  return month === 1 ? year - 1 : year - 1;
}