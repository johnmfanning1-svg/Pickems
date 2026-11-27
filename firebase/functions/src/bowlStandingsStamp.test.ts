import { describe, expect, it } from "vitest";
import { accumulateMemberTotals } from "./memberSeasonTotals";

describe("bowlStandingsStamp scoring", () => {
  it("uses stamped value on bowl week even when live rules flipped", () => {
    const scores = new Map([
      ["2026-BOWL1", new Map([["u1", { wins: 2, losses: 0 }]])],
    ]);
  const { season, bowl } = accumulateMemberTotals(
      { bowlSeason: { countsTowardSeasonStandings: false } },
      [{ weekId: "2026-BOWL1", countsTowardSeasonStandingsAtScore: true }],
      scores
    );
    expect(bowl.get("u1")).toEqual({ wins: 2, losses: 0 });
    expect(season.get("u1")).toEqual({ wins: 2, losses: 0 });
  });
});