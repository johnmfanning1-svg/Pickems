import { describe, it, expect } from "vitest";
import {
  parseCompetitorScore,
  parseEventScores,
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
