import { describe, expect, it } from "vitest";
import {
  espnScoreboardWeek,
  includesGame,
  isWeekZeroKickoff,
  resolveAppWeekNumber,
  splitPickMap,
  submissionCoversSlate,
} from "./cfbWeekCalendar";

describe("espnScoreboardWeek", () => {
  it("maps week 0 onto ESPN week 1", () => {
    expect(espnScoreboardWeek(0)).toBe(1);
    expect(espnScoreboardWeek(1)).toBe(1);
    expect(espnScoreboardWeek(2)).toBe(2);
  });
});

describe("resolveAppWeekNumber", () => {
  it("uses week 0 before Aug 30 2026", () => {
    expect(
      resolveAppWeekNumber({
        seasonYear: 2026,
        espnWeekNumber: 1,
        now: new Date("2026-08-28T16:00:00.000Z"),
      })
    ).toBe(0);
  });

  it("uses week 1 on Aug 30 2026", () => {
    expect(
      resolveAppWeekNumber({
        seasonYear: 2026,
        espnWeekNumber: 1,
        now: new Date("2026-08-30T04:00:00.000Z"),
      })
    ).toBe(1);
  });

  it("passes ESPN week 2 and 2027 through", () => {
    expect(
      resolveAppWeekNumber({
        seasonYear: 2026,
        espnWeekNumber: 2,
        now: new Date("2026-09-08T16:00:00.000Z"),
      })
    ).toBe(2);
    expect(
      resolveAppWeekNumber({
        seasonYear: 2027,
        espnWeekNumber: 1,
        now: new Date("2027-08-28T16:00:00.000Z"),
      })
    ).toBe(1);
  });
});

describe("week 0 date filter", () => {
  it("keeps Aug 29 on week 0 and later games on week 1", () => {
    const aug29 = new Date("2026-08-29T16:00:00.000Z"); // noon ET
    const sep5 = new Date("2026-09-05T16:00:00.000Z");
    expect(isWeekZeroKickoff(aug29)).toBe(true);
    expect(includesGame({ kickoff: aug29, seasonYear: 2026, appWeekNumber: 0 })).toBe(true);
    expect(includesGame({ kickoff: sep5, seasonYear: 2026, appWeekNumber: 0 })).toBe(false);
    expect(includesGame({ kickoff: aug29, seasonYear: 2026, appWeekNumber: 1 })).toBe(false);
    expect(includesGame({ kickoff: sep5, seasonYear: 2026, appWeekNumber: 1 })).toBe(true);
  });
});

describe("splitPickMap / submissions", () => {
  it("splits pick maps and detects incomplete remaining slates", () => {
    const weekZeroIds = new Set(["a", "b"]);
    const split = splitPickMap({ a: "home", b: "away", c: "home" }, weekZeroIds);
    expect(split.weekZero).toEqual({ a: "home", b: "away" });
    expect(split.weekOne).toEqual({ c: "home" });
    expect(submissionCoversSlate(split.weekOne, ["c"])).toBe(true);
    expect(submissionCoversSlate(split.weekOne, ["c", "d"])).toBe(false);
  });

  it("second split of an already-split map is a no-op for week 0 keys", () => {
    const weekZeroIds = new Set(["a"]);
    const split = splitPickMap({ c: "home" }, weekZeroIds);
    expect(split.weekZero).toEqual({});
    expect(split.weekOne).toEqual({ c: "home" });
  });
});
