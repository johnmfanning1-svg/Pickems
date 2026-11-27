import { describe, expect, it } from "vitest";
import {
  bowlCountsTowardSeason,
  bowlWeekId,
  isBowlWeekId,
  parseBowlWeekId,
  bowlSortWeekNumber,
} from "./bowlWeek";
import { weekWindow } from "./cfbWeekWindow";

describe("bowlWeek", () => {
  it("parses bowl ids", () => {
    expect(parseBowlWeekId("2026-BOWL1")).toEqual({ seasonYear: 2026, slot: "BOWL1" });
    expect(isBowlWeekId("2026-W15")).toBe(false);
    expect(bowlWeekId(2026, "BOWL2")).toBe("2026-BOWL2");
  });

  it("reads season standings toggle", () => {
    expect(bowlCountsTowardSeason({ bowlSeason: { countsTowardSeasonStandings: true } })).toBe(true);
    expect(bowlCountsTowardSeason({ bowlSeason: { countsTowardSeasonStandings: false } })).toBe(false);
  });

  it("exposes bowl windows for default selection deadlines", () => {
    const w1 = weekWindow(2026, bowlSortWeekNumber("BOWL1"));
    const w2 = weekWindow(2026, bowlSortWeekNumber("BOWL2"));
    expect(w1).not.toBeNull();
    expect(w2).not.toBeNull();
  });
});