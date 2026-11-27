/** ESPN-shaped CFB week windows — keep in sync with iOS `CFBWeekCalendar` / `CFBWeekDateWindow`. */

const MONTH: Record<string, number> = {
  jan: 1,
  feb: 2,
  mar: 3,
  apr: 4,
  may: 5,
  jun: 6,
  jul: 7,
  aug: 8,
  sep: 9,
  oct: 10,
  nov: 11,
  dec: 12,
};

const ESPN_2026: Array<{ weekNumber: number; label: string }> = [
  { weekNumber: 0, label: "Aug 29" },
  { weekNumber: 1, label: "Sep 3-7" },
  { weekNumber: 2, label: "Sep 8-13" },
  { weekNumber: 3, label: "Sep 14-20" },
  { weekNumber: 4, label: "Sep 21-27" },
  { weekNumber: 5, label: "Sep 28-Oct 4" },
  { weekNumber: 6, label: "Oct 5-11" },
  { weekNumber: 7, label: "Oct 12-18" },
  { weekNumber: 8, label: "Oct 19-25" },
  { weekNumber: 9, label: "Oct 26-Nov 1" },
  { weekNumber: 10, label: "Nov 2-8" },
  { weekNumber: 11, label: "Nov 9-15" },
  { weekNumber: 12, label: "Nov 16-22" },
  { weekNumber: 13, label: "Nov 23-29" },
  { weekNumber: 14, label: "Nov 30-Dec 6" },
  { weekNumber: 15, label: "Dec 7-12" },
  { weekNumber: 901, label: "Dec 12-Jan 1" },
  { weekNumber: 902, label: "Jan 2-Jan 25" },
];

/** Bowl week windows (ESPN postseason). Keep in sync with iOS `CFBWeekCalendar` bowl labels. */
const BOWL_2026_WINDOWS: Record<string, string> = {
  BOWL1: "Dec 13-Jan 25",
  BOWL2: "Dec 18-Jan 28",
  BOWL: "Dec 13-Jan 25",
};

function seasonKickoffEastern(seasonYear: number): Date {
  const day = seasonYear === 2026 ? 29 : seasonYear === 2025 ? 23 : 28;
  return easternWallTime(seasonYear, 8, day, 0, 0, 0, 0);
}

/** Wall time in America/New_York as absolute instant. */
export function easternWallTime(
  year: number,
  month: number,
  day: number,
  hour = 0,
  minute = 0,
  second = 0,
  ms = 0
): Date {
  let guess = Date.UTC(year, month - 1, day, hour, minute, second, ms);
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
  const read = (d: Date) => {
    const parts = Object.fromEntries(fmt.formatToParts(d).map((p) => [p.type, p.value]));
    return {
      year: Number(parts.year),
      month: Number(parts.month),
      day: Number(parts.day),
      hour: Number(parts.hour === "24" ? "0" : parts.hour),
      minute: Number(parts.minute),
      second: Number(parts.second),
    };
  };
  const targetMs = Date.UTC(year, month - 1, day, hour, minute, second, ms);
  for (let i = 0; i < 48; i++) {
    const got = read(new Date(guess));
    const gotMs = Date.UTC(got.year, got.month - 1, got.day, got.hour, got.minute, got.second);
    const delta = targetMs - gotMs;
    if (delta === 0) return new Date(guess);
    guess += delta;
  }
  return new Date(guess);
}

function parseDayToken(token: string, defaultYear: number, anchorMonth?: number): { y: number; m: number; d: number } | null {
  const parts = token.trim().split(/\s+/);
  if (parts.length !== 2) return null;
  const month = MONTH[parts[0].toLowerCase()];
  const day = Number(parts[1]);
  if (!month || !Number.isFinite(day)) return null;
  let year = defaultYear;
  if (anchorMonth != null && month < anchorMonth) year += 1;
  return { y: year, m: month, d: day };
}

export function parseWeekLabel(label: string, seasonYear: number): { start: Date; end: Date } | null {
  const trimmed = label.trim();
  if (trimmed.startsWith("Week ")) {
    const n = Number(trimmed.replace("Week ", ""));
    if (!Number.isFinite(n) || n < 1) return null;
    const kickoff = seasonKickoffEastern(seasonYear);
    const start = new Date(kickoff.getTime() + (n - 1) * 7 * 24 * 3600_000);
    const end = new Date(start.getTime() + 6 * 24 * 3600_000);
    const startParts = easternYmd(start);
    const endParts = easternYmd(end);
    return {
      start: easternWallTime(startParts.year, startParts.month, startParts.day, 0, 0, 0, 0),
      end: easternWallTime(endParts.year, endParts.month, endParts.day, 23, 59, 59, 999),
    };
  }
  if (trimmed.includes("-")) {
    const [a, b] = trimmed.split("-", 2);
    const startParts = parseDayToken(a, seasonYear);
    if (!startParts) return null;
    let endParts: { y: number; m: number; d: number };
    if (b.includes(" ")) {
      const parsed = parseDayToken(b, seasonYear, startParts.m);
      if (!parsed) return null;
      endParts = parsed;
    } else {
      const endDay = Number(b.trim());
      if (!Number.isFinite(endDay)) return null;
      endParts = { y: startParts.y, m: startParts.m, d: endDay };
    }
    return {
      start: easternWallTime(startParts.y, startParts.m, startParts.d, 0, 0, 0, 0),
      end: easternWallTime(endParts.y, endParts.m, endParts.d, 23, 59, 59, 999),
    };
  }
  const day = parseDayToken(trimmed, seasonYear);
  if (!day) return null;
  return {
    start: easternWallTime(day.y, day.m, day.d, 0, 0, 0, 0),
    end: easternWallTime(day.y, day.m, day.d, 23, 59, 59, 999),
  };
}

function easternYmd(date: Date): { year: number; month: number; day: number } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
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

export function weekWindow(seasonYear: number, weekNumber: number): { start: Date; end: Date } | null {
  if (seasonYear === 2026) {
    const slot = ESPN_2026.find((w) => w.weekNumber === weekNumber);
    if (!slot) return null;
    return parseWeekLabel(slot.label, seasonYear);
  }
  return parseWeekLabel(`Week ${weekNumber}`, seasonYear);
}

export function weekWindowForPickemsWeek(
  weekId: string,
  seasonYear: number,
  weekNumber: number
): { start: Date; end: Date } | null {
  const bowl = weekId.match(/^\d{4}-(BOWL\d*)$/i);
  if (bowl) {
    const key = bowl[1].toUpperCase();
    const label = BOWL_2026_WINDOWS[key];
    if (label) return parseWeekLabel(label, seasonYear);
  }
  return weekWindow(seasonYear, weekNumber);
}