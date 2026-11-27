import { describe, expect, it } from "vitest";
import {
  BOWL_SEASON_DEFAULTS,
  BOWL_USER_FACING_WEEK_NAME,
  bowlCountsTowardSeason,
  bowlSeasonConfigured,
  bowlWeekId,
  isBowlFullSlateWeek,
  isBowlWeekId,
  parseBowlWeekId,
  resolveBowlSeasonRules,
  userFacingWeekLabel,
  espnPostseasonWeekForBowlWeekId,
  ESPN_BOWL2_POSTSEASON_WEEK,
  ESPN_POSTSEASON_WEEK,
} from "./bowlWeek";
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
    expect(bowlCountsTowardSeason({})).toBe(false);
  });

  it("treats missing bowlSeason as Mode A enabled", () => {
    expect(resolveBowlSeasonRules(null)).toEqual(BOWL_SEASON_DEFAULTS);
    expect(resolveBowlSeasonRules(undefined)).toEqual(BOWL_SEASON_DEFAULTS);
    expect(bowlSeasonConfigured({})).toBe(true);
    expect(bowlSeasonConfigured(undefined)).toBe(true);
  });

  it("respects explicit commissioner off", () => {
    expect(bowlSeasonConfigured({ bowlSeason: { isEnabled: false, mode: "modeA" } })).toBe(false);
    expect(resolveBowlSeasonRules({ isEnabled: false, mode: "modeA" }).isEnabled).toBe(false);
  });

  it("treats Mode B as configured when enabled", () => {
    expect(bowlSeasonConfigured({ bowlSeason: { isEnabled: true, mode: "modeB" } })).toBe(true);
    expect(parseBowlWeekId("2026-BOWL")).toEqual({ seasonYear: 2026, slot: "BOWL" });
  });

  it("isBowlFullSlateWeek requires 2026-BOWL id", () => {
    const week = { bowlFullSlate: true, slateSource: "bowlCatalog" };
    expect(isBowlFullSlateWeek(week, "2026-BOWL")).toBe(true);
    expect(isBowlFullSlateWeek(week, "2026-BOWL1")).toBe(false);
  });

  it("maps bowl week ids to ESPN postseason scoreboard weeks", () => {
    expect(espnPostseasonWeekForBowlWeekId("2026-BOWL1")).toBe(ESPN_POSTSEASON_WEEK);
    expect(espnPostseasonWeekForBowlWeekId("2026-BOWL2")).toBe(ESPN_BOWL2_POSTSEASON_WEEK);
  });

  it("labels bowl weeks for notifications", () => {
    expect(userFacingWeekLabel("2026-BOWL1", 1)).toBe(BOWL_USER_FACING_WEEK_NAME);
    expect(userFacingWeekLabel("2026-W7", 7)).toBe("Week 7");
  });

  it("exposes bowl windows for default selection deadlines", () => {
    const w1 = weekWindowForPickemsWeek("2026-BOWL1", 2026, 1);
    const w2 = weekWindowForPickemsWeek("2026-BOWL2", 2026, 2);
    expect(w1).not.toBeNull();
    expect(w2).not.toBeNull();
  });
});