import { weekWindow } from "./cfbWeekWindow";
import { isFixedSlate } from "./cfbWeekCalendar";

export const DEFAULT_SELECTION_STAMP = "default";

export interface DefaultSelectionLock {
  enabled: boolean;
  weekday: number;
  hour: number;
  minute: number;
  timeZone: string;
}

/** Raw instant inside the week window, including past. Null when the weekday is missing from the window. */
export function defaultSelectionDeadline(
  lock: DefaultSelectionLock | null | undefined,
  seasonYear: number,
  weekNumber: number
): Date | null {
  if (!lock?.enabled) return null;
  const window = weekWindow(seasonYear, weekNumber);
  if (!window) return null;

  try {
    let { year, month, day } = zonedParts(window.start, lock.timeZone);
    const end = zonedParts(window.end, lock.timeZone);
    while (true) {
      const probe = zonedWallTimeFromParts(year, month, day, lock.timeZone, 0, 0);
      if (isoWeekday(probe, lock.timeZone) === lock.weekday) {
        return zonedWallTimeFromParts(year, month, day, lock.timeZone, lock.hour, lock.minute);
      }
      if (year > end.year || (year === end.year && month > end.month) ||
          (year === end.year && month === end.month && day >= end.day)) {
        return null;
      }
      ({ year, month, day } = addCalendarDay(year, month, day));
    }
  } catch {
    return null;
  }
}

export function futureDefaultSelectionDeadline(
  lock: DefaultSelectionLock | null | undefined,
  seasonYear: number,
  weekNumber: number,
  nowMs: number = Date.now()
): Date | null {
  const raw = defaultSelectionDeadline(lock, seasonYear, weekNumber);
  if (!raw) return null;
  return raw.getTime() > nowMs ? raw : null;
}

export function leagueHasDefaultSelectionLock(rules: { defaultSelectionLock?: DefaultSelectionLock | null } | undefined): boolean {
  return rules?.defaultSelectionLock?.enabled === true;
}

export function shouldStampDefaultSelection(params: {
  lock: DefaultSelectionLock | null | undefined;
  selectionMode?: string;
  weekNumber?: number;
  slateSource?: string | null;
  status?: string;
  existingDeadline?: unknown;
}): boolean {
  if (params.existingDeadline) return false;
  if (params.status && params.status !== "selection") return false;
  if (params.selectionMode !== "member") return false;
  if (isFixedSlate(params.weekNumber ?? -1, params.slateSource)) return false;
  return leagueHasDefaultSelectionLock({ defaultSelectionLock: params.lock ?? undefined });
}

function addCalendarDay(year: number, month: number, day: number): { year: number; month: number; day: number } {
  const next = new Date(Date.UTC(year, month - 1, day + 1));
  return { year: next.getUTCFullYear(), month: next.getUTCMonth() + 1, day: next.getUTCDate() };
}

function isoWeekday(date: Date, timeZone: string): number {
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone, weekday: "short" });
  const short = fmt.format(date);
  const map: Record<string, number> = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };
  return map[short] ?? 0;
}

function zonedParts(date: Date, timeZone: string): { year: number; month: number; day: number } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  return {
    year: Number(parts.find((p) => p.type === "year")?.value ?? "0"),
    month: Number(parts.find((p) => p.type === "month")?.value ?? "0"),
    day: Number(parts.find((p) => p.type === "day")?.value ?? "0"),
  };
}

function zonedWallTimeFromParts(
  year: number,
  month: number,
  day: number,
  timeZone: string,
  hour: number,
  minute: number
): Date {
  let guess = Date.UTC(year, month - 1, day, hour, minute, 0, 0);
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
  const targetMs = Date.UTC(year, month - 1, day, hour, minute, 0, 0);
  for (let i = 0; i < 48; i++) {
    const got = Object.fromEntries(fmt.formatToParts(new Date(guess)).map((p) => [p.type, p.value]));
    const gotMs = Date.UTC(
      Number(got.year),
      Number(got.month) - 1,
      Number(got.day),
      Number(got.hour === "24" ? "0" : got.hour),
      Number(got.minute),
      Number(got.second)
    );
    const delta = targetMs - gotMs;
    if (delta === 0) return new Date(guess);
    guess += delta;
  }
  return new Date(guess);
}