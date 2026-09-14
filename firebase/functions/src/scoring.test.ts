import { describe, it, expect } from "vitest";
import {
  coveredTeamId,
  scorePicks,
  rankEntries,
  computeWeekAwards,
  applyLatePickPenalty,
  toMillis,
  membersOnRoster,
  isWeekZero,
  missedPickIsLossForSeasonWeek,
  resolvePickMode,
  resolveWeekPickMode,
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

describe("resolvePickMode", () => {
  it("defaults missing values to ats", () => {
    expect(resolvePickMode(undefined)).toBe("ats");
    expect(resolvePickMode("ats")).toBe("ats");
    expect(resolvePickMode("straightUp")).toBe("straightUp");
    expect(resolvePickMode("other")).toBe("ats");
  });
});

describe("resolveWeekPickMode", () => {
  it("inherits the league type when the week has no override", () => {
    expect(resolveWeekPickMode(undefined, "ats")).toBe("ats");
    expect(resolveWeekPickMode(undefined, "straightUp")).toBe("straightUp");
  });

  it("lets an ATS league score one week straight up", () => {
    expect(resolveWeekPickMode("straightUp", "ats")).toBe("straightUp");
  });

  it("does not let a Straight Up league fall back to ATS for one week", () => {
    expect(resolveWeekPickMode("ats", "straightUp")).toBe("straightUp");
  });
});

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

  it("straight up ignores the spread and pushes on a tie", () => {
    const g = game({ id: "1" });
    expect(coveredTeamId(g, 24, 17, "straightUp")).toBe("home");
    expect(coveredTeamId(g, 21, 24, "straightUp")).toBe("away");
    expect(coveredTeamId(g, 17, 17, "straightUp")).toBeNull();
    expect(coveredTeamId(g, 24, 17, "ats")).toBeNull();
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

  it("counts a missing Pickem on a final slate game as a loss", () => {
    const g1 = game({ id: "g1" });
    const g2 = game({ id: "g2", homeScore: 10, awayScore: 21, winnerTeamId: "away" });
    expect(scorePicks({ g1: "home" }, [g1, g2])).toEqual({ wins: 1, losses: 1, pushes: 0 });
    expect(scorePicks({}, [g1, g2])).toEqual({ wins: 0, losses: 2, pushes: 0 });
    expect(scorePicks({ g2: "   " }, [g1, g2])).toEqual({ wins: 0, losses: 2, pushes: 0 });
  });

  it("counts a missed Pickem as a loss even when the spread pushes", () => {
    const g = game({ id: "g1", homeScore: 24, awayScore: 17 });
    expect(scorePicks({}, [g])).toEqual({ wins: 0, losses: 1, pushes: 0 });
  });

  it("straight up scores the outright winner and treats a tie as a push", () => {
    const coverPush = game({ id: "g1", homeScore: 24, awayScore: 17 });
    expect(scorePicks({ g1: "home" }, [coverPush], null, { pickMode: "straightUp" })).toEqual({
      wins: 1,
      losses: 0,
      pushes: 0,
    });
    expect(scorePicks({ g1: "away" }, [coverPush], null, { pickMode: "straightUp" })).toEqual({
      wins: 0,
      losses: 1,
      pushes: 0,
    });
    const tie = game({ id: "g1", homeScore: 21, awayScore: 21 });
    expect(scorePicks({ g1: "home" }, [tie], null, { pickMode: "straightUp" })).toEqual({
      wins: 0,
      losses: 0,
      pushes: 1,
    });
    expect(scorePicks({}, [tie], null, { pickMode: "straightUp" })).toEqual({
      wins: 0,
      losses: 1,
      pushes: 0,
    });
  });

  it("does not double a missed confidence game", () => {
    const g = game({ id: "g1" });
    expect(scorePicks({}, [g], "g1")).toEqual({ wins: 0, losses: 1, pushes: 0 });
  });

  it("can skip missed Pickems when re-summing historical Week 0", () => {
    const g = game({ id: "g1" });
    expect(scorePicks({}, [g], null, { missedPickIsLoss: false })).toEqual({
      wins: 0,
      losses: 0,
      pushes: 0,
    });
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

function standing(overrides: {
  id: string;
  displayName: string;
  weeklyWins: number;
  weeklyLosses: number;
  seasonWins?: number;
  seasonLosses?: number;
}) {
  return {
    avatarColorHex: "#111",
    seasonWins: overrides.seasonWins ?? overrides.weeklyWins,
    seasonLosses: overrides.seasonLosses ?? overrides.weeklyLosses,
    ...overrides,
  };
}

describe("rankEntries", () => {
  it("orders by weekly wins then name, not batting average", () => {
    const ranked = rankEntries([
      standing({ id: "a", displayName: "Amy", weeklyWins: 4, weeklyLosses: 4 }),
      standing({ id: "b", displayName: "Bob", weeklyWins: 4, weeklyLosses: 2 }),
    ]);
    expect(ranked.map((e) => e.id)).toEqual(["a", "b"]);
    expect(ranked.map((e) => e.rank)).toEqual([1, 1]);
    expect(ranked[1].isTied).toBe(true);
  });

  it("ranks more wins ahead of a hotter batting average", () => {
    const ranked = rankEntries([
      standing({
        id: "late",
        displayName: "Late",
        weeklyWins: 8,
        weeklyLosses: 0,
        seasonWins: 8,
        seasonLosses: 0,
      }),
      standing({
        id: "vet",
        displayName: "Veteran",
        weeklyWins: 10,
        weeklyLosses: 10,
        seasonWins: 10,
        seasonLosses: 10,
      }),
    ]);
    expect(ranked.map((e) => e.id)).toEqual(["vet", "late"]);
    expect(ranked[0].rank).toBe(1);
    expect(ranked[1].rank).toBe(2);
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

  it("straight up heartbreaker uses raw score margin", () => {
    const games = [game({ id: "1", homeScore: 24, awayScore: 21, spread: 14 })];
    const picks: PickDoc[] = [
      { userId: "a", displayName: "Alex", picks: { "1": "home" } },
      { userId: "b", displayName: "Blake", picks: { "1": "away" } },
    ];
    expect(computeWeekAwards(picks, games, "straightUp").sharpshooterUserId).toBe("a");
    expect(computeWeekAwards(picks, games, "straightUp").heartbreakerUserId).toBe("b");
  });
});

describe("weekZeroRescoreGuard", () => {
  it("detects Week 0 ids and numbers", () => {
    expect(isWeekZero("2026-W0", 0)).toBe(true);
    expect(isWeekZero("2026-W1", 1)).toBe(false);
    expect(isWeekZero("2026-W2", 2)).toBe(false);
  });

  it("keeps skip-miss math when a later week re-sums Week 0", () => {
    expect(
      missedPickIsLossForSeasonWeek({
        targetWeekId: "2026-W2",
        targetWeekNumber: 2,
        seasonWeekId: "2026-W0",
        seasonWeekNumber: 0,
      })
    ).toBe(false);
    expect(
      missedPickIsLossForSeasonWeek({
        targetWeekId: "2026-W2",
        targetWeekNumber: 2,
        seasonWeekId: "2026-W1",
        seasonWeekNumber: 1,
      })
    ).toBe(true);
  });
});

describe("membersOnRoster", () => {
  it("drops leftover member docs who are not in memberIds", () => {
    const members = [
      { id: "a", displayName: "Alex" },
      { id: "jack", displayName: "JBanda" },
    ];
    expect(membersOnRoster(members, ["a"]).map((m) => m.id)).toEqual(["a"]);
  });

  it("keeps the full list when memberIds is empty", () => {
    const members = [{ id: "a" }, { id: "b" }];
    expect(membersOnRoster(members, []).map((m) => m.id)).toEqual(["a", "b"]);
    expect(membersOnRoster(members, undefined).map((m) => m.id)).toEqual(["a", "b"]);
  });
});
