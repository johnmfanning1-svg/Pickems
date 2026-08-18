/** Shared 2026 Week 0 overlay. Keep in sync with iOS `CFBWeekCalendar`. */

export const WEEK_ZERO_SLATE_SOURCE = "fixedBoard";
export const WEEK_ZERO_YEAR = 2026;
export const WEEK_ZERO_ID = "2026-W0";
export const WEEK_ONE_ID = "2026-W1";

/** Sunday Aug 30, 2026 00:00 America/New_York (EDT = UTC-4). */
export const WEEK_ZERO_WINDOW_END = new Date("2026-08-30T04:00:00.000Z");

export function espnScoreboardWeek(appWeekNumber: number): number {
  return appWeekNumber === 0 ? 1 : appWeekNumber;
}

export function resolveAppWeekNumber(options: {
  seasonYear: number;
  espnWeekNumber: number;
  now?: Date;
}): number {
  const { seasonYear, espnWeekNumber, now = new Date() } = options;
  if (seasonYear !== WEEK_ZERO_YEAR || espnWeekNumber !== 1) return espnWeekNumber;
  return now < WEEK_ZERO_WINDOW_END ? 0 : 1;
}

export function easternYmd(date: Date): { year: number; month: number; day: number } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const year = Number(parts.find((p) => p.type === "year")?.value ?? "0");
  const month = Number(parts.find((p) => p.type === "month")?.value ?? "0");
  const day = Number(parts.find((p) => p.type === "day")?.value ?? "0");
  return { year, month, day };
}

export function isWeekZeroKickoff(date: Date): boolean {
  const { year, month, day } = easternYmd(date);
  return year === 2026 && month === 8 && day === 29;
}

export function includesGame(options: {
  kickoff: Date;
  seasonYear: number;
  appWeekNumber: number;
}): boolean {
  const { kickoff, seasonYear, appWeekNumber } = options;
  if (seasonYear !== WEEK_ZERO_YEAR || (appWeekNumber !== 0 && appWeekNumber !== 1)) {
    return true;
  }
  const isZero = isWeekZeroKickoff(kickoff);
  return appWeekNumber === 0 ? isZero : !isZero;
}

export function isFixedSlate(weekNumber: number, slateSource?: string | null): boolean {
  return weekNumber === 0 || slateSource === WEEK_ZERO_SLATE_SOURCE;
}

export function splitPickMap(
  picks: Record<string, string>,
  weekZeroEventIds: Set<string>
): { weekZero: Record<string, string>; weekOne: Record<string, string> } {
  const weekZero: Record<string, string> = {};
  const weekOne: Record<string, string> = {};
  for (const [eventId, teamId] of Object.entries(picks)) {
    if (weekZeroEventIds.has(eventId)) weekZero[eventId] = teamId;
    else weekOne[eventId] = teamId;
  }
  return { weekZero, weekOne };
}

export function submissionCoversSlate(
  picks: Record<string, string>,
  slateEventIds: string[]
): boolean {
  if (slateEventIds.length === 0) return false;
  return slateEventIds.every((id) => {
    const team = picks[id];
    return typeof team === "string" && team.trim().length > 0;
  });
}

export function earliestKickoff(dates: Date[]): Date | null {
  if (dates.length === 0) return null;
  return dates.reduce((min, d) => (d < min ? d : min));
}
