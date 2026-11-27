import { describe, expect, it } from "vitest";
import { accumulateMemberTotals, bowlStandingsToggleShouldLock } from "./memberSeasonTotals";

describe("memberSeasonTotals", () => {
  it("rebuilds season and bowl buckets when bowls count toward season", () => {
    const scores = new Map([
      ["2026-W14", new Map([["u1", { wins: 5, losses: 2 }]])],
      ["2026-BOWL1", new Map([["u1", { wins: 3, losses: 1 }]])],
    ]);
    const { season, bowl } = accumulateMemberTotals(
      { bowlSeason: { countsTowardSeasonStandings: true } },
      [
        { weekId: "2026-W14" },
        { weekId: "2026-BOWL1" },
      ],
      scores
    );
    expect(season.get("u1")).toEqual({ wins: 8, losses: 3 });
    expect(bowl.get("u1")).toEqual({ wins: 3, losses: 1 });
  });

  it("keeps bowl picks out of season when bowls are separate", () => {
    const scores = new Map([
      ["2026-W14", new Map([["u1", { wins: 5, losses: 2 }]])],
      ["2026-BOWL1", new Map([["u1", { wins: 2, losses: 0 }]])],
    ]);
    const { season, bowl } = accumulateMemberTotals(
      { bowlSeason: { countsTowardSeasonStandings: false } },
      [
        { weekId: "2026-W14" },
        { weekId: "2026-BOWL1" },
      ],
      scores
    );
    expect(season.get("u1")).toEqual({ wins: 5, losses: 2 });
    expect(bowl.get("u1")).toEqual({ wins: 2, losses: 0 });
  });

  it("locks standings toggle after any scored bowl week", () => {
    expect(bowlStandingsToggleShouldLock(["2026-W15"])).toBe(false);
    expect(bowlStandingsToggleShouldLock(["2026-BOWL1"])).toBe(true);
  });

  it("regular week rescore aggregation preserves bowl totals from other bowl weeks", () => {
    const scores = new Map([
      ["2026-W14", new Map([["u1", { wins: 4, losses: 2 }]])],
      ["2026-BOWL1", new Map([["u1", { wins: 2, losses: 1 }]])],
      ["2026-BOWL2", new Map([["u1", { wins: 1, losses: 0 }]])],
    ]);
    const { bowl, season } = accumulateMemberTotals(
      { bowlSeason: { countsTowardSeasonStandings: false } },
      [{ weekId: "2026-W14" }, { weekId: "2026-BOWL1" }, { weekId: "2026-BOWL2" }],
      scores
    );
    expect(bowl.get("u1")).toEqual({ wins: 3, losses: 1 });
    expect(season.get("u1")).toEqual({ wins: 4, losses: 2 });
  });

  it("rescore BOWL1 aggregation still includes BOWL2 bowl totals", () => {
    const scores = new Map([
      ["2026-BOWL1", new Map([["u1", { wins: 5, losses: 0 }]])],
      ["2026-BOWL2", new Map([["u1", { wins: 2, losses: 2 }]])],
    ]);
    const { bowl } = accumulateMemberTotals(
      { bowlSeason: { countsTowardSeasonStandings: false } },
      [{ weekId: "2026-BOWL1" }, { weekId: "2026-BOWL2" }],
      scores
    );
    expect(bowl.get("u1")).toEqual({ wins: 7, losses: 2 });
  });
});