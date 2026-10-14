import { describe, it, expect } from "vitest";
import {
  parseCompetitorScore,
  parseEventScores,
  parseLineScoreList,
  nextGameStatus,
  slateGameNeedsWrite,
  scoreboardURL,
  resolveSpreadTeamId,
  type EspnEvent,
} from "./espn";

function event(overrides: {
  homeScore?: string;
  awayScore?: string;
  completed?: boolean;
  state?: string;
}): EspnEvent {
  return {
    id: "401",
    competitions: [
      {
        competitors: [
          {
            id: "h",
            homeAway: "home",
            score: overrides.homeScore,
            team: { id: "home", displayName: "Home", abbreviation: "HOM" },
          },
          {
            id: "a",
            homeAway: "away",
            score: overrides.awayScore,
            team: { id: "away", displayName: "Away", abbreviation: "AWY" },
          },
        ],
        status: {
          type: { completed: overrides.completed, state: overrides.state },
        },
      },
    ],
  };
}

describe("scoreboardURL", () => {
  it("matches the iOS client query shape", () => {
    const url = new URL(scoreboardURL({ week: 1, seasonType: 2 }));
    expect(url.searchParams.get("groups")).toBe("80");
    expect(url.searchParams.get("limit")).toBe("300");
    expect(url.searchParams.get("week")).toBe("1");
    expect(url.searchParams.get("seasontype")).toBe("2");
  });
});

describe("parseCompetitorScore", () => {
  it("does not coerce missing or garbage scores to 0", () => {
    expect(parseCompetitorScore(undefined)).toBeNull();
    expect(parseCompetitorScore("")).toBeNull();
    expect(parseCompetitorScore("n/a")).toBeNull();
    expect(parseCompetitorScore("21")).toBe(21);
  });
});

describe("parseEventScores / nextGameStatus", () => {
  it("keeps scheduled when ESPN marks complete without scores", () => {
    const parsed = parseEventScores(event({ completed: true, state: "post" }));
    expect(parsed?.homeScore).toBeNull();
    expect(parsed?.awayScore).toBeNull();
    expect(nextGameStatus("scheduled", parsed)).toBe("scheduled");
  });

  it("marks final only when complete and both scores exist", () => {
    const parsed = parseEventScores(
      event({ homeScore: "28", awayScore: "17", completed: true, state: "post" })
    );
    expect(nextGameStatus("inProgress", parsed)).toBe("final");
  });

  // KNOWN ISSUE (October audit): parseEventScores sets completed when state is
  // "post", so a postponed game that still carries score strings (often "0") is
  // marked final. Intended: completed:false must not finalize a game.
  it.fails("does not finalize a state-post game whose completed flag is false", () => {
    const parsed = parseEventScores(
      event({ homeScore: "0", awayScore: "0", completed: false, state: "post" })
    );
    expect(nextGameStatus("scheduled", parsed)).not.toBe("final");
  });

  it("keeps a delayed game scheduled while ESPN state is still pre", () => {
    const parsed = parseEventScores(
      event({ homeScore: "0", awayScore: "0", completed: false, state: "pre" })
    );
    expect(parsed?.completed).toBe(false);
    expect(nextGameStatus("scheduled", parsed)).toBe("scheduled");
  });

  // KNOWN ISSUE (October audit): a canceled game reported as a completed 0-0 is
  // marked final today. Intended: a 0-0 "final" must not be graded as final.
  it.fails("does not mark a completed 0-0 (canceled) game final", () => {
    const parsed = parseEventScores(
      event({ homeScore: "0", awayScore: "0", completed: true, state: "post" })
    );
    expect(nextGameStatus("scheduled", parsed)).not.toBe("final");
  });
});

describe("parseLineScoreList", () => {
  it("reads ESPN value objects and drops a broken period", () => {
    expect(parseLineScoreList([{ value: 7 }, { displayValue: "3" }, { value: 0 }])).toEqual([7, 3, 0]);
    expect(parseLineScoreList([{ value: 7 }, { value: "nope" }])).toBeNull();
    expect(parseLineScoreList([])).toBeNull();
    expect(parseLineScoreList(undefined)).toBeNull();
  });

  it("attaches linescores without inventing them", () => {
    const withPeriods = parseEventScores({
      id: "401",
      competitions: [
        {
          competitors: [
            {
              id: "h",
              homeAway: "home",
              score: "28",
              linescores: [{ value: 7 }, { value: 14 }, { value: 7 }, { value: 0 }],
              team: { id: "home", displayName: "Home", abbreviation: "HOM" },
            },
            {
              id: "a",
              homeAway: "away",
              score: "17",
              linescores: [{ value: 0 }, { value: 3 }, { value: 7 }, { value: 7 }],
              team: { id: "away", displayName: "Away", abbreviation: "AWY" },
            },
          ],
          status: { type: { completed: true, state: "post" } },
        },
      ],
    });
    expect(withPeriods?.homeLineScores).toEqual([7, 14, 7, 0]);
    expect(withPeriods?.awayLineScores).toEqual([0, 3, 7, 7]);

    const missing = parseEventScores(event({ homeScore: "28", awayScore: "17", completed: true, state: "post" }));
    expect(missing?.homeLineScores).toBeNull();
    expect(missing?.awayLineScores).toBeNull();
  });
});

describe("slateGameNeedsWrite", () => {
  const parsed = {
    homeScore: 14,
    awayScore: 21,
    homeTeamId: "home",
    awayTeamId: "away",
    completed: false,
    inProgress: true,
  };

  it("writes when only the away score moved", () => {
    expect(
      slateGameNeedsWrite(
        { status: "inProgress", homeScore: 14, awayScore: 17 },
        "inProgress",
        parsed
      )
    ).toBe(true);
  });

  it("skips when nothing changed", () => {
    expect(
      slateGameNeedsWrite(
        { status: "inProgress", homeScore: 14, awayScore: 21 },
        "inProgress",
        parsed
      )
    ).toBe(false);
  });
});

describe("resolveSpreadTeamId", () => {
  it("uses home favorite flag even when spread is negative", () => {
    expect(
      resolveSpreadTeamId({
        homeTeamId: "30",
        awayTeamId: "23",
        spread: -38.5,
        homeFavorite: true,
        awayFavorite: false,
      })
    ).toBe("30");
  });

  it("uses away favorite flag when home flag is absent", () => {
    expect(
      resolveSpreadTeamId({
        homeTeamId: "home",
        awayTeamId: "away",
        spread: 3.5,
        awayFavorite: true,
      })
    ).toBe("away");
  });

  it("does not default to away when favorite flags are missing and spread is negative", () => {
    expect(
      resolveSpreadTeamId({
        homeTeamId: "30",
        awayTeamId: "23",
        spread: -38.5,
      })
    ).toBe("30");
  });

  it("treats a positive home-centric spread as away favored", () => {
    expect(
      resolveSpreadTeamId({
        homeTeamId: "home",
        awayTeamId: "away",
        spread: 7.5,
      })
    ).toBe("away");
  });
});
