import { describe, it, expect } from "vitest";
import {
  coveredTeamId,
  scorePicks,
  rankEntries,
  computeWeekAwards,
  applyLatePickPenalty,
  toMillis,
  type SlateGameDoc,
  type PickDoc,
} from "./scoring";

function game(overrides: Partial<SlateGameDoc> & Pick<SlateGameDoc, "id">): SlateGameDoc {
  return {
    espnEventId: overrides.id,
    homeTeamId: "home",
    awayTeamId: "away",
    spread: 7,
    spreadTeamId: "home",
    status: "final",
    homeScore: 28,
    awayScore: 17,
    winnerTeamId: "home",
    ...overrides,
  };
}

describe("coveredTeamId", () => {
  it("favorite covers when margin beats the spread", () => {
    const g = game({ id: "1" });
    expect(coveredTeamId(g, 28, 17)).toBe("home");
  });

  it("returns null on a push", () => {
    const g = game({ id: "1" });
    expect(coveredTeamId(g, 24, 17)).toBeNull();
  });

  it("underdog covers when favorite fails to cover", () => {
    const g = game({ id: "1", spread: 3.5 });
    expect(coveredTeamId(g, 21, 24)).toBe("away");
  });
});

describe("scorePicks", () => {
  it("skips non-final games instead of counting pushes", () => {
    const scheduled = game({ id: "g1", status: "scheduled", homeScore: null, awayScore: null });
    expect(scorePicks({ g1: "home" }, [scheduled])).toEqual({ wins: 0, losses: 0, pushes: 0 });
  });

  it("doubles wins for the confidence game", () => {
    const g = game({ id: "g1" });
    expect(scorePicks({ g1: "home" }, [g]).wins).toBe(1);
    expect(scorePicks({ g1: "home" }, [g], "g1").wins).toBe(2);
  });

  it("counts a spread push", () => {
    const g = game({ id: "g1", homeScore: 24, awayScore: 17 });
    expect(scorePicks({ g1: "home" }, [g])).toEqual({ wins: 0, losses: 0, pushes: 1 });
  });
});

describe("applyLatePickPenalty", () => {
  it("subtracts wins when submitted after the deadline", () => {
    const scored = applyLatePickPenalty(
      { wins: 8, losses: 4, pushes: 0 },
      {
        allowLatePicks: true,
        latePickPenaltyWins: 1,
        submittedAt: 2_000,
        deadline: 1_000,
      }
    );
    expect(scored.wins).toBe(7);
  });

  it("does not go below zero wins", () => {
    const scored = applyLatePickPenalty(
      { wins: 0, losses: 12, pushes: 0 },
      {
        allowLatePicks: true,
        latePickPenaltyWins: 2,
        submittedAt: 2_000,
        deadline: 1_000,
      }
    );
    expect(scored.wins).toBe(0);
  });

  it("does nothing when late picks are disabled", () => {
    const scored = applyLatePickPenalty(
      { wins: 8, losses: 4, pushes: 0 },
      {
        allowLatePicks: false,
        latePickPenaltyWins: 1,
        submittedAt: 2_000,
        deadline: 1_000,
      }
    );
    expect(scored.wins).toBe(8);
  });
});

describe("toMillis", () => {
  it("reads Date, number, and Timestamp-like values", () => {
    expect(toMillis(1_000)).toBe(1_000);
    expect(toMillis(new Date(5_000))).toBe(5_000);
    expect(toMillis({ toMillis: () => 9_000 })).toBe(9_000);
    expect(toMillis(undefined)).toBeNull();
  });
});

describe("rankEntries", () => {
  it("orders by weekly wins then batting average then name", () => {
    const ranked = rankEntries([
      {
        id: "a",
        displayName: "Amy",
        avatarColorHex: "#111",
        weeklyWins: 4,
        weeklyLosses: 4,
        seasonWins: 4,
        seasonLosses: 4,
      },
      {
        id: "b",
        displayName: "Bob",
        avatarColorHex: "#222",
        weeklyWins: 4,
        weeklyLosses: 2,
        seasonWins: 4,
        seasonLosses: 2,
      },
    ]);
    expect(ranked.map((e) => e.id)).toEqual(["b", "a"]);
    expect(ranked[0].rank).toBe(1);
  });
});

describe("computeWeekAwards", () => {
  it("picks the sharpshooter with the most wins", () => {
    const games = [game({ id: "1", homeScore: 30, awayScore: 10, spread: 3 })];
    const picks: PickDoc[] = [
      { userId: "a", displayName: "Alex", picks: { "1": "home" } },
      { userId: "b", displayName: "Blake", picks: { "1": "away" } },
    ];
    expect(computeWeekAwards(picks, games).sharpshooterUserId).toBe("a");
  });
});
