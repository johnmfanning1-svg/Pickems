import { describe, expect, it } from "vitest";
import {
  DEFAULT_SELECTION_STAMP,
  defaultSelectionDeadline,
  leagueHasDefaultSelectionLock,
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

  it("detects league default", () => {
    expect(leagueHasDefaultSelectionLock({ defaultSelectionLock: lock })).toBe(true);
    expect(leagueHasDefaultSelectionLock({ defaultSelectionLock: { ...lock, enabled: false } })).toBe(false);
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