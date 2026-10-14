import { describe, expect, it } from "vitest";
import { coveredTeamId, scorePicks, type SlateGameDoc } from "./scoring";
import {
  gameEffectivelyLocked,
  gradingLine,
  lockedSpreadPatch,
  movementCaption,
  oddsRefreshPatch,
  phaseLockedGameIds,
  planLeagueSpreadWrite,
  rejectedPickIds,
  spreadDisplayLabel,
  weekLevelLocked,
} from "./spreadLock";

const NOW = Date.parse("2026-10-10T16:00:00Z");
const PAST = NOW - 60_000;
const FUTURE = NOW + 60 * 60 * 1000;

function openWeek(overrides: Record<string, unknown> = {}) {
  return {
    status: "picking",
    pickLockMode: "firstKickoff",
    pickDeadline: FUTURE,
    ...overrides,
  };
}

function slateGame(overrides: Partial<SlateGameDoc> = {}): SlateGameDoc {
  return {
    id: "g1",
    espnEventId: "g1",
    homeTeamId: "home",
    awayTeamId: "away",
    homeTeamAbbreviation: "HOM",
    awayTeamAbbreviation: "AWY",
    spread: 7,
    spreadTeamId: "home",
    status: "final",
    homeScore: 24,
    awayScore: 20,
    kickoff: PAST,
    ...overrides,
  };
}

describe("league spread lock", () => {
  it("lets a commissioner edit the line before kickoff", () => {
    const write = planLeagueSpreadWrite({
      week: openWeek(),
      game: { id: "sun", kickoff: FUTURE, status: "scheduled" },
      now: NOW,
      spread: 3.5,
      spreadTeamId: "away",
    });
    expect(write).toEqual({
      allowed: true,
      patch: { spread: 3.5, spreadTeamId: "away" },
    });
  });

  it("rejects a commissioner edit after kickoff or lock", () => {
    const kicked = planLeagueSpreadWrite({
      week: openWeek(),
      game: { id: "thu", kickoff: PAST, status: "scheduled" },
      now: NOW,
      spread: 10,
      spreadTeamId: "home",
    });
    expect(kicked).toEqual({ allowed: false, reason: "locked" });

    const started = planLeagueSpreadWrite({
      week: openWeek(),
      game: { id: "thu", kickoff: FUTURE, status: "inProgress" },
      now: NOW,
      spread: 10,
      spreadTeamId: "home",
    });
    expect(started).toEqual({ allowed: false, reason: "locked" });

    const weekLocked = planLeagueSpreadWrite({
      week: openWeek({ status: "locked" }),
      game: { id: "sun", kickoff: FUTURE, status: "pre" },
      now: NOW,
      spread: 10,
      spreadTeamId: "home",
    });
    expect(weekLocked).toEqual({ allowed: false, reason: "locked" });
  });

  it("keeps grading on the locked line after the live line moves", () => {
    const game = slateGame({
      spread: 14,
      spreadTeamId: "away",
      lockedSpread: 3,
      lockedSpreadTeamId: "home",
      liveSpread: 6.5,
      liveSpreadTeamId: "home",
    });
    expect(gradingLine(game)).toEqual({ spread: 3, spreadTeamId: "home" });
    expect(coveredTeamId(game, 24, 20)).toBe("home");
    expect(scorePicks({ g1: "home" }, [game])).toEqual({ wins: 1, losses: 0, pushes: 0 });
    expect(scorePicks({ g1: "away" }, [game])).toEqual({ wins: 0, losses: 1, pushes: 0 });

    const moved = oddsRefreshPatch(game, { liveSpread: 9.5, liveSpreadTeamId: "away" });
    expect(moved).toEqual({ liveSpread: 9.5, liveSpreadTeamId: "away" });
    expect(moved && "spread" in moved).toBe(false);
    expect(moved && "lockedSpread" in moved).toBe(false);
    expect(gradingLine({ ...game, ...moved })).toEqual({ spread: 3, spreadTeamId: "home" });
    expect(coveredTeamId({ ...game, ...moved, spread: 14, spreadTeamId: "away" }, 24, 20)).toBe("home");
  });

  it("falls back to spread when a locked game has no lockedSpread yet", () => {
    const legacy = slateGame({ spread: 7, spreadTeamId: "home" });
    expect(gradingLine(legacy)).toEqual({ spread: 7, spreadTeamId: "home" });
    expect(coveredTeamId(legacy, 24, 17)).toBeNull();
  });

  it("captures the line at lock and clears it when the game unlocks", () => {
    const open = slateGame({
      status: "scheduled",
      kickoff: FUTURE,
      spread: 6.5,
      spreadTeamId: "away",
    });
    expect(lockedSpreadPatch(open, false)).toBeNull();
    expect(lockedSpreadPatch(open, true)).toEqual({
      op: "set",
      lockedSpread: 6.5,
      lockedSpreadTeamId: "away",
    });
    const frozen = { ...open, lockedSpread: 6.5, lockedSpreadTeamId: "away" };
    expect(lockedSpreadPatch(frozen, true)).toBeNull();
    expect(lockedSpreadPatch(frozen, false)).toEqual({ op: "clear" });
  });

  it("allows an edit again after the week unlocks a game that has not kicked off", () => {
    const upcoming = { id: "sun", kickoff: FUTURE, status: "scheduled" as const };
    expect(gameEffectivelyLocked(openWeek({ status: "locked" }), upcoming, NOW)).toBe(true);
    expect(
      planLeagueSpreadWrite({
        week: openWeek({ status: "locked" }),
        game: upcoming,
        now: NOW,
        spread: 4,
        spreadTeamId: "home",
      }).allowed
    ).toBe(false);

    const reopened = openWeek({ status: "picking", pickDeadline: FUTURE });
    expect(weekLevelLocked(reopened, NOW)).toBe(false);
    expect(gameEffectivelyLocked(reopened, upcoming, NOW)).toBe(false);
    expect(
      planLeagueSpreadWrite({
        week: reopened,
        game: upcoming,
        now: NOW,
        spread: 4,
        spreadTeamId: "home",
      })
    ).toEqual({ allowed: true, patch: { spread: 4, spreadTeamId: "home" } });
  });

  it("keeps a started game locked when the week is unlocked mid-week", () => {
    const reopened = openWeek();
    const started = { id: "thu", kickoff: PAST, status: "in" as const };
    const upcoming = { id: "sun", kickoff: FUTURE, status: "pre" as const };
    expect(gameEffectivelyLocked(reopened, started, NOW)).toBe(true);
    expect(gameEffectivelyLocked(reopened, upcoming, NOW)).toBe(false);

    expect(
      planLeagueSpreadWrite({
        week: reopened,
        game: started,
        now: NOW,
        spread: 2,
        spreadTeamId: "home",
      })
    ).toEqual({ allowed: false, reason: "locked" });

    const games = [
      slateGame({ id: "thu", kickoff: PAST, status: "inProgress", spread: 7, lockedSpread: 7, lockedSpreadTeamId: "home" }),
      slateGame({ id: "sun", kickoff: FUTURE, status: "scheduled", spread: 3, spreadTeamId: "away" }),
    ];
    expect(
      rejectedPickIds({
        week: reopened,
        games,
        before: { thu: "home", sun: "away" },
        after: { thu: "away", sun: "home" },
        now: NOW,
      })
    ).toEqual(["thu"]);
    expect(
      rejectedPickIds({
        week: reopened,
        games,
        before: { thu: "home", sun: "away" },
        after: { thu: "home", sun: "home" },
        now: NOW,
      })
    ).toEqual([]);

    const refresh = oddsRefreshPatch(games[0], { liveSpread: 10, liveSpreadTeamId: "away" });
    expect(refresh).toEqual({ liveSpread: 10, liveSpreadTeamId: "away" });
    expect(gradingLine({ ...games[0], ...refresh, spread: 21, spreadTeamId: "away" })).toEqual({
      spread: 7,
      spreadTeamId: "home",
    });
    expect(lockedSpreadPatch({ ...games[0], ...refresh }, true)).toBeNull();
  });

  it("still updates the parenthetical movement line", () => {
    const lockedLabel = spreadDisplayLabel({
      spread: 7,
      spreadTeamId: "home",
      homeTeamId: "home",
      awayTeamId: "away",
      homeAbbr: "HOM",
      awayAbbr: "AWY",
    });
    expect(movementCaption(lockedLabel, null)).toBe("HOM -7.0");
    const refresh = oddsRefreshPatch(
      { liveSpread: 7, liveSpreadTeamId: "home" },
      { liveSpread: 6.5, liveSpreadTeamId: "home" }
    );
    expect(refresh?.liveSpread).toBe(6.5);
    const liveLabel = spreadDisplayLabel({
      spread: refresh?.liveSpread ?? 7,
      spreadTeamId: refresh?.liveSpreadTeamId ?? "home",
      homeTeamId: "home",
      awayTeamId: "away",
      homeAbbr: "HOM",
      awayAbbr: "AWY",
    });
    expect(movementCaption(lockedLabel, liveLabel)).toBe("HOM -7.0 (HOM -6.5)");
    expect(movementCaption(lockedLabel, "HOM -7")).toBe("HOM -7.0");
  });
});

describe("phaseLockedGameIds", () => {
  it("lists only games that have left pregame", () => {
    expect(
      phaseLockedGameIds([
        { id: "pre", status: "scheduled" },
        { id: "soon", status: "pre" },
        { id: "live", status: "in" },
        { id: "playing", status: "inProgress" },
        { id: "done", status: "final" },
        { id: "", status: "in" },
      ])
    ).toEqual(["live", "playing", "done"]);
  });
});
