import { describe, expect, it } from "vitest";
import {
  countsTowardSeasonStandingsAtScoreForNewlyScoredWeek,
  COUNTS_TOWARD_SEASON_AT_SCORE,
} from "./bowlStandingsStamp";
import { accumulateMemberTotals } from "./memberSeasonTotals";

describe("countsTowardSeasonStandingsAtScoreForNewlyScoredWeek", () => {
  it("prefers group stamp from another scored bowl week over live rules", () => {
    const groupWeeks = [
      {
        id: "2026-BOWL1",
        data: { status: "scored", [COUNTS_TOWARD_SEASON_AT_SCORE]: false },
      },
      { id: "2026-BOWL2", data: { status: "locked" } },
    ];
    expect(
      countsTowardSeasonStandingsAtScoreForNewlyScoredWeek(
        { bowlSeason: { countsTowardSeasonStandings: true } },
        "2026-BOWL2",
        groupWeeks[1].data,
        groupWeeks
      )
    ).toBe(false);
  });

  it("uses live rules when no group stamp exists", () => {
    const groupWeeks = [{ id: "2026-BOWL2", data: { status: "locked" } }];
    expect(
      countsTowardSeasonStandingsAtScoreForNewlyScoredWeek(
        { bowlSeason: { countsTowardSeasonStandings: true } },
        "2026-BOWL2",
        groupWeeks[0].data,
        groupWeeks
      )
    ).toBe(true);
    expect(
      countsTowardSeasonStandingsAtScoreForNewlyScoredWeek(
        { bowlSeason: { countsTowardSeasonStandings: false } },
        "2026-BOWL2",
        groupWeeks[0].data,
        groupWeeks
      )
    ).toBe(false);
  });
});

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