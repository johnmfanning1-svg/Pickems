/** Shared season-close rules for `autoCloseSeasons` (tested here, wired in `index.ts`). */

export const POSTSEASON_SEASON_TYPE = 3;

/** ESPN postseason week 1 must not map onto regular-season `2026-W1`. */
export function espnPostseasonWouldMintRegularWeekOne(seasonYear: number, espnWeekNumber: number, seasonType: number): boolean {
  return seasonYear === 2026 && seasonType === POSTSEASON_SEASON_TYPE && espnWeekNumber === 1;
}

export function isBowlWeekDocumentId(weekId: string): boolean {
  return /^\d{4}-BOWL\d*$/i.test(weekId);
}

function isStalePlaceholderBowlWeek(week: Record<string, unknown>): boolean {
  if (week.status !== "selection") return false;
  const gameIds = week.gameIds;
  const hasSlate = Array.isArray(gameIds) && gameIds.length > 0;
  const nominations =
    typeof week.nominationCount === "number" ? week.nominationCount : 0;
  const hasDeadline = week.selectionDeadline != null;
  return !hasSlate && nominations === 0 && !hasDeadline;
}

/** Active bowl weeks block archive; empty selection placeholders do not. */
export function isOpenBowlWeek(weekId: string, week: Record<string, unknown>): boolean {
  if (!isBowlWeekDocumentId(weekId)) return false;
  if (week.status === "scored") return false;
  if (isStalePlaceholderBowlWeek(week)) return false;
  return week.status === "selection" || week.status === "picking" || week.status === "locked";
}

/** Cloud Scheduler cron — daily at noon Eastern through February (retries after skip). */
export const AUTO_CLOSE_SEASONS_SCHEDULE = "0 12 * 2 *";

export function isAutoCloseSeasonsRunMonth(runAt: Date, timeZone = "America/New_York"): boolean {
  const month = Number(
    new Intl.DateTimeFormat("en-US", { timeZone, month: "numeric" }).format(runAt)
  );
  return month === 2;
}

export function groupShouldSkipAutoClose(
  weeks: Array<{ id: string; data: Record<string, unknown> }>
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