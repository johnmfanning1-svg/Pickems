import { describe, expect, it } from "vitest";
import { bowlCountsTowardSeason, bowlWeekId, isBowlWeekId, parseBowlWeekId } from "./bowlWeek";
import { weekWindowForPickemsWeek } from "./cfbWeekWindow";

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
    const w1 = weekWindowForPickemsWeek("2026-BOWL1", 2026, 1);
    const w2 = weekWindowForPickemsWeek("2026-BOWL2", 2026, 2);
    expect(w1).not.toBeNull();
    expect(w2).not.toBeNull();
  });
});