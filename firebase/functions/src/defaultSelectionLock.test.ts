import { describe, expect, it } from "vitest";
import {
  DEFAULT_SELECTION_STAMP,
  defaultSelectionDeadline,
  futureDefaultSelectionDeadline,
  shouldStampDefaultSelection,
} from "./defaultSelectionLock";

describe("defaultSelectionLock", () => {
  const lock = {
    enabled: true,
    weekday: 3,
    hour: 23,
    minute: 59,
    timeZone: "America/New_York",
  };

  it("computes Wednesday in 2026 week 3", () => {
    const d = defaultSelectionDeadline(lock, 2026, 3);
    expect(d).not.toBeNull();
    const fmt = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      weekday: "short",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).formatToParts(d!);
    const day = Object.fromEntries(fmt.map((p) => [p.type, p.value]));
    expect(day.weekday).toBe("Wed");
    expect(day.month).toBe("09");
    expect(day.day).toBe("16");
    expect(day.hour).toBe("23");
    expect(day.minute).toBe("59");
  });

  it("returns null when weekday is missing in week window (2026 W1 Wed)", () => {
    expect(defaultSelectionDeadline(lock, 2026, 1)).toBeNull();
  });

  it("future helper rejects past instants", () => {
    const raw = defaultSelectionDeadline(lock, 2026, 3);
    expect(raw).not.toBeNull();
    const afterDeadlineMs = raw!.getTime() + 60_000;
    expect(futureDefaultSelectionDeadline(lock, 2026, 3, afterDeadlineMs)).toBeNull();
    const beforeDeadlineMs = raw!.getTime() - 60_000;
    expect(futureDefaultSelectionDeadline(lock, 2026, 3, beforeDeadlineMs)?.getTime()).toBe(
      raw!.getTime()
    );
  });

  it("handles invalid time zone safely", () => {
    const bad = { ...lock, timeZone: "Not/A_Zone" };
    expect(defaultSelectionDeadline(bad, 2026, 3)).toBeNull();
  });

  it("parity table weeks 0–15 for Thursday 7pm Eastern", () => {
    const thuLock = { enabled: true, weekday: 4, hour: 19, minute: 0, timeZone: "America/New_York" };
    const expectations: Record<number, string | null> = {
      0: null,
      1: "2026-09-03",
      2: "2026-09-10",
      3: "2026-09-17",
      10: "2026-11-05",
      15: "2026-12-10",
    };
    for (const [weekStr, ymd] of Object.entries(expectations)) {
      const week = Number(weekStr);
      const d = defaultSelectionDeadline(thuLock, 2026, week);
      if (ymd === null) {
        expect(d).toBeNull();
        continue;
      }
      expect(d).not.toBeNull();
      const parts = new Intl.DateTimeFormat("en-US", {
        timeZone: "America/New_York",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }).formatToParts(d!);
      const got = Object.fromEntries(parts.map((p) => [p.type, p.value]));
      const expectedYmd = `${got.year}-${got.month}-${got.day}`;
      expect(expectedYmd).toBe(ymd);
    }
  });

  it("DST week 10 Tuesday 6pm Eastern", () => {
    const tue = { enabled: true, weekday: 2, hour: 18, minute: 0, timeZone: "America/New_York" };
    const d = defaultSelectionDeadline(tue, 2026, 10);
    expect(d).not.toBeNull();
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      hour12: false,
    }).formatToParts(d!);
    const got = Object.fromEntries(parts.map((p) => [p.type, p.value]));
    expect(got.month).toBe("11");
    expect(got.day).toBe("03");
    expect(got.hour).toBe("18");
  });

  it("skips week zero and commissioner mode", () => {
    expect(
      shouldStampDefaultSelection({
        lock,
        selectionMode: "member",
        weekNumber: 0,
        slateSource: "fixedBoard",
        status: "selection",
      })
    ).toBe(false);
    expect(
      shouldStampDefaultSelection({
        lock,
        selectionMode: "commissioner",
        weekNumber: 3,
        status: "selection",
      })
    ).toBe(false);
  });

  it("uses default stamp constant", () => {
    expect(DEFAULT_SELECTION_STAMP).toBe("default");
  });
});