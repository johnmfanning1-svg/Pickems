import { describe, expect, it } from "vitest";
import {
  LINE_POOLS,
  MAX_PUSH_BODY_LENGTH,
  MAX_PUSH_TITLE_LENGTH,
  THRESHOLDS,
  classifyGameFinal,
  gameFinalPushCopy,
  periodInputFromGame,
  readLastSpicyGameFinal,
  renderScenarioLines,
  resolveSpicyAlerts,
  stableHash,
  type GameFinalCopyInput,
  type GameFinalScenario,
} from "./pushCopy";

const SCENARIOS = Object.keys(LINE_POOLS) as GameFinalScenario[];

function game(overrides: GameFinalCopyInput = {}): GameFinalCopyInput {
  return {
    userId: "user-1",
    gameId: "game-1",
    groupId: "group-1",
    pickMode: "ats",
    spicyAlerts: true,
    pickedTeamId: "home",
    homeTeamId: "home",
    awayTeamId: "away",
    homeTeamName: "Ohio State",
    awayTeamName: "Michigan",
    homeTeamAbbreviation: "OSU",
    awayTeamAbbreviation: "MICH",
    homeScore: 24,
    awayScore: 21,
    spread: 7,
    spreadTeamId: "home",
    ...overrides,
  };
}

describe("thresholds", () => {
  it("locks the owner-editable cutoffs", () => {
    expect(THRESHOLDS).toEqual({
      blowout: 14,
      badBeat: 3,
      hook: 0.5,
      bigFavorite: 14,
      upsetDog: 7,
      dominant: 14,
      backdoor: 3,
    });
  });
});

describe("ATS losses", () => {
  it("classifies a 14-point cover miss as a blowout, including an outright win that never covered", () => {
    const crushed = classifyGameFinal(game({ spread: 3, homeScore: 10, awayScore: 28 }));
    expect(crushed.scenario).toBe("blowout_loss");
    expect(crushed.signedMargin).toBe(-21);

    const noCover = classifyGameFinal(game({ spread: 21, homeScore: 24, awayScore: 21 }));
    expect(noCover.scenario).toBe("blowout_loss");
    expect(noCover.signedMargin).toBe(-18);
    expect(noCover.result).toBe("missed");
  });

  it("treats a miss of 14 as a blowout and 13 as a plain loss", () => {
    expect(classifyGameFinal(game({ spread: 7, homeScore: 14, awayScore: 21 })).scenario).toBe("blowout_loss");
    expect(classifyGameFinal(game({ spread: 6, homeScore: 14, awayScore: 21 })).scenario).toBe("plain_loss");
  });

  it("classifies a miss of 3 or the hook as a bad beat, and 3.5 as plain", () => {
    const byThree = classifyGameFinal(game({ spread: 7, homeScore: 24, awayScore: 20 }));
    expect(byThree).toMatchObject({ scenario: "bad_beat", signedMargin: -3, hook: false });

    const hook = classifyGameFinal(game({ spread: 6.5, homeScore: 27, awayScore: 21 }));
    expect(hook).toMatchObject({ scenario: "bad_beat", signedMargin: -0.5, hook: true });

    const justOutside = classifyGameFinal(game({ spread: 3.5, homeScore: 21, awayScore: 21 }));
    expect(justOutside).toMatchObject({ scenario: "plain_loss", signedMargin: -3.5, hook: false });
  });

  it("calls a 14-point favorite losing outright an upset, ahead of the blowout", () => {
    const upset = classifyGameFinal(game({ spread: 21, homeScore: 10, awayScore: 24 }));
    expect(upset.scenario).toBe("upset_loss");
    expect(upset.signedMargin).toBe(-35);

    expect(classifyGameFinal(game({ spread: 14, homeScore: 17, awayScore: 20 })).scenario).toBe("upset_loss");
    expect(classifyGameFinal(game({ spread: 13.5, homeScore: 20, awayScore: 21 })).scenario).toBe("blowout_loss");
  });

  it("does not call a tie an outright upset", () => {
    expect(classifyGameFinal(game({ spread: 14, homeScore: 21, awayScore: 21 })).scenario).toBe("blowout_loss");
  });

  it("uses a blown lead when period data shows one, and ignores it when they only failed to cover", () => {
    const ledThenLost = game({
      spread: 3,
      homeScore: 20,
      awayScore: 24,
      homeLineScores: [10, 7, 3, 0],
      awayLineScores: [0, 3, 7, 14],
    });
    expect(classifyGameFinal(ledThenLost)).toMatchObject({ scenario: "blown_lead", blownLead: true });
    expect(classifyGameFinal({ ...ledThenLost, homeLineScores: undefined, awayLineScores: undefined }).scenario).toBe(
      "plain_loss"
    );

    const ledAndWonTheGame = classifyGameFinal(
      game({
        spread: 14,
        homeScore: 24,
        awayScore: 17,
        homeLineScores: [14, 7, 3, 0],
        awayLineScores: [0, 0, 7, 10],
      })
    );
    expect(ledAndWonTheGame).toMatchObject({ scenario: "plain_loss", blownLead: false, signedMargin: -7 });
  });

  it("accepts a lead after three quarters, cumulative linescores, and explicit halftime fields", () => {
    const afterThree = classifyGameFinal(
      game({
        spread: 3,
        homeScore: 21,
        awayScore: 28,
        homeLineScores: [7, 7, 7, 0],
        awayLineScores: [0, 7, 7, 14],
      })
    );
    expect(afterThree.scenario).toBe("blown_lead");

    const cumulative = classifyGameFinal(
      game({
        spread: 3,
        homeScore: 21,
        awayScore: 28,
        homeLineScores: [14, 21, 21, 21],
        awayLineScores: [0, 7, 14, 28],
      })
    );
    expect(cumulative.scenario).toBe("blown_lead");

    const explicit = classifyGameFinal(
      game({
        spread: 3,
        homeScore: 21,
        awayScore: 28,
        halftimeHomeScore: 21,
        halftimeAwayScore: 7,
      })
    );
    expect(explicit.scenario).toBe("blown_lead");
  });

  it("ignores a single period and a tied halftime that never led", () => {
    expect(
      classifyGameFinal(
        game({
          spread: 3,
          homeScore: 17,
          awayScore: 21,
          homeLineScores: [17],
          awayLineScores: [21],
        })
      ).scenario
    ).toBe("plain_loss");

    expect(
      classifyGameFinal(
        game({
          spread: 3,
          homeScore: 17,
          awayScore: 24,
          halftimeHomeScore: 14,
          halftimeAwayScore: 14,
        })
      ).scenario
    ).toBe("plain_loss");
  });
});

describe("ATS wins and pushes", () => {
  it("calls an underdog of 7+ that wins outright an upset, ahead of dominant and backdoor", () => {
    const called = classifyGameFinal(
      game({ pickedTeamId: "away", spread: 7, spreadTeamId: "home", homeScore: 21, awayScore: 24 })
    );
    expect(called).toMatchObject({ scenario: "upset_win", signedMargin: 10 });

    expect(
      classifyGameFinal(
        game({ pickedTeamId: "away", spread: 10, spreadTeamId: "home", homeScore: 21, awayScore: 22 })
      ).scenario
    ).toBe("upset_win");

    expect(
      classifyGameFinal(
        game({ pickedTeamId: "away", spread: 7, spreadTeamId: "home", homeScore: 10, awayScore: 31 })
      ).scenario
    ).toBe("upset_win");

    expect(
      classifyGameFinal(
        game({ pickedTeamId: "away", spread: 6.5, spreadTeamId: "home", homeScore: 10, awayScore: 31 })
      ).scenario
    ).toBe("dominant_win");
  });

  it("classifies a cover of 3 or fewer as a backdoor and 14+ as dominant", () => {
    expect(classifyGameFinal(game({ spread: 3, homeScore: 24, awayScore: 20 })).scenario).toBe("backdoor_win");
    expect(classifyGameFinal(game({ spread: 7, homeScore: 31, awayScore: 21 })).scenario).toBe("backdoor_win");
    expect(classifyGameFinal(game({ spread: 6.5, homeScore: 28, awayScore: 21 })).signedMargin).toBe(0.5);
    expect(classifyGameFinal(game({ spread: 6.5, homeScore: 28, awayScore: 21 })).scenario).toBe("backdoor_win");
    expect(classifyGameFinal(game({ spread: 6.5, homeScore: 31, awayScore: 21 })).scenario).toBe("plain_win");
    expect(classifyGameFinal(game({ spread: 7, homeScore: 35, awayScore: 14 })).scenario).toBe("dominant_win");
    expect(classifyGameFinal(game({ spread: 3, homeScore: 38, awayScore: 21 })).scenario).toBe("dominant_win");
  });

  it("treats a late flip under 14 as a backdoor and a comeback blowout as dominant", () => {
    const sneaky = classifyGameFinal(
      game({
        spread: 3,
        homeScore: 31,
        awayScore: 21,
        homeLineScores: [0, 0, 0, 31],
        awayLineScores: [7, 7, 7, 0],
      })
    );
    expect(sneaky).toMatchObject({ scenario: "backdoor_win", lateFlip: true, signedMargin: 7 });

    const comeback = classifyGameFinal(
      game({
        spread: 3,
        homeScore: 45,
        awayScore: 7,
        homeLineScores: [0, 0, 0, 45],
        awayLineScores: [7, 0, 0, 0],
      })
    );
    expect(comeback).toMatchObject({ scenario: "dominant_win", lateFlip: true });

    const halftimeOnly = classifyGameFinal(
      game({
        spread: 3,
        homeScore: 24,
        awayScore: 17,
        homeLineScores: [0, 3],
        awayLineScores: [7, 7],
      })
    );
    expect(halftimeOnly).toMatchObject({ scenario: "backdoor_win", lateFlip: true, signedMargin: 4 });
  });

  it("pushes when the score lands on the number", () => {
    const push = classifyGameFinal(game({ spread: 7, homeScore: 28, awayScore: 21 }));
    expect(push).toMatchObject({ scenario: "push", result: "push", signedMargin: 0 });
  });
});

describe("straight up", () => {
  const su = (overrides: GameFinalCopyInput = {}) => game({ pickMode: "straightUp", ...overrides });

  it("uses the score margin instead of the cover margin", () => {
    expect(classifyGameFinal(su({ homeScore: 10, awayScore: 31, spread: 3 })).scenario).toBe("blowout_loss");
    expect(classifyGameFinal(su({ homeScore: 17, awayScore: 30, spread: 3 })).scenario).toBe("plain_loss");
    expect(classifyGameFinal(su({ homeScore: 21, awayScore: 24, spread: 3 })).scenario).toBe("bad_beat");
    expect(classifyGameFinal(su({ homeScore: 20, awayScore: 24, spread: 3 })).scenario).toBe("plain_loss");
    expect(classifyGameFinal(su({ homeScore: 35, awayScore: 17, spread: 3 })).scenario).toBe("dominant_win");
    expect(classifyGameFinal(su({ homeScore: 24, awayScore: 21, spread: 3 })).scenario).toBe("backdoor_win");
    expect(classifyGameFinal(su({ homeScore: 28, awayScore: 24, spread: 3 })).scenario).toBe("plain_win");
    expect(classifyGameFinal(su({ homeScore: 21, awayScore: 21 })).scenario).toBe("push");
  });

  it("prefers the upset over a close score or a blowout", () => {
    expect(classifyGameFinal(su({ spread: 21, homeScore: 24, awayScore: 27 })).scenario).toBe("upset_loss");
    expect(classifyGameFinal(su({ spread: 21, homeScore: 7, awayScore: 35 })).scenario).toBe("upset_loss");
    expect(classifyGameFinal(su({ spread: 13.5, homeScore: 21, awayScore: 24 })).scenario).toBe("bad_beat");
    expect(
      classifyGameFinal(su({ pickedTeamId: "away", spreadTeamId: "home", spread: 7, homeScore: 20, awayScore: 21 }))
        .scenario
    ).toBe("upset_win");
    expect(
      classifyGameFinal(su({ pickedTeamId: "away", spreadTeamId: "home", spread: 7, homeScore: 7, awayScore: 35 }))
        .scenario
    ).toBe("upset_win");
    expect(
      classifyGameFinal(su({ pickedTeamId: "away", spreadTeamId: "home", spread: 6.5, homeScore: 7, awayScore: 28 }))
        .scenario
    ).toBe("dominant_win");
  });

  it("still spots a blown lead and a late flip from period scores", () => {
    expect(
      classifyGameFinal(
        su({
          spread: 3,
          homeScore: 21,
          awayScore: 28,
          homeLineScores: [14, 7, 0, 0],
          awayLineScores: [0, 0, 14, 14],
        })
      ).scenario
    ).toBe("blown_lead");

    const late = classifyGameFinal(
      su({
        spread: 3,
        homeScore: 31,
        awayScore: 21,
        homeLineScores: [0, 0, 7, 24],
        awayLineScores: [7, 7, 7, 0],
      })
    );
    expect(late).toMatchObject({ scenario: "backdoor_win", lateFlip: true, signedMargin: 10 });
  });

  it("has no hook", () => {
    expect(classifyGameFinal(su({ homeScore: 21, awayScore: 22, spread: 0.5 })).hook).toBe(false);
  });
});

describe("fallbacks", () => {
  it("drops to the plain result when the spread or the side cannot be scored", () => {
    expect(
      classifyGameFinal(game({ spread: undefined, winnerTeamId: "home", homeScore: 31, awayScore: 10 })).scenario
    ).toBe("plain_win");
    expect(
      classifyGameFinal(game({ spreadTeamId: "nobody", winnerTeamId: "away", homeScore: 10, awayScore: 31 })).scenario
    ).toBe("plain_loss");
    expect(
      classifyGameFinal(
        game({ homeScore: undefined, awayScore: undefined, winnerTeamId: "home", spread: undefined })
      )
    ).toMatchObject({ scenario: "plain_win", result: "covered", signedMargin: null });
    expect(
      classifyGameFinal(game({ pickedTeamId: "not-in-game", winnerTeamId: "home", homeScore: 31, awayScore: 10 }))
        .scenario
    ).toBe("plain_loss");
  });

  it("keeps straight-up margin when the favorite is unknown", () => {
    expect(
      classifyGameFinal(
        game({ pickMode: "straightUp", spread: undefined, spreadTeamId: undefined, homeScore: 10, awayScore: 31 })
      ).scenario
    ).toBe("blowout_loss");
  });

  it("never throws", () => {
    expect(() => gameFinalPushCopy(null)).not.toThrow();
    expect(() => gameFinalPushCopy(undefined)).not.toThrow();
    expect(() =>
      classifyGameFinal({
        homeScore: "nope",
        spread: { bad: true },
        pickedTeamId: 4,
        homeLineScores: [1, "x"],
        pickMode: "sideways",
      })
    ).not.toThrow();
    const fallback = gameFinalPushCopy({ spicyAlerts: false });
    expect(fallback).toEqual({ title: "Push", body: "AWAY @ HOME is final." });
    expect(gameFinalPushCopy(undefined).title.length).toBeGreaterThan(0);
    expect(gameFinalPushCopy(undefined).body.length).toBeLessThanOrEqual(MAX_PUSH_BODY_LENGTH);
  });
});

describe("plain copy", () => {
  it("matches the existing titles and body when spicy alerts are off", () => {
    const covered = game({ spicyAlerts: false, spread: 3, homeScore: 31, awayScore: 10 });
    expect(gameFinalPushCopy(covered)).toEqual({ title: "You covered", body: "MICH @ OSU is final." });
    expect(gameFinalPushCopy({ ...covered, pickMode: "straightUp" })).toEqual({
      title: "You won",
      body: "MICH @ OSU is final.",
    });
    expect(gameFinalPushCopy(game({ spicyAlerts: false, spread: 21, homeScore: 10, awayScore: 31 }))).toEqual({
      title: "Tough beat",
      body: "MICH @ OSU is final.",
    });
    expect(gameFinalPushCopy(game({ spicyAlerts: false, spread: 7, homeScore: 28, awayScore: 21 }))).toEqual({
      title: "Push",
      body: "MICH @ OSU is final.",
    });
  });
});

describe("line pools", () => {
  const longNames = game({
    homeTeamName: "North Carolina State",
    awayTeamName: "South Carolina State",
    homeTeamAbbreviation: "NCST",
    awayTeamAbbreviation: "SCST",
    homeScore: 99,
    awayScore: 98,
    spread: 45.5,
  });

  it("keeps a distinct lock-screen line for every trimmed pool", () => {
    const expected: Record<GameFinalScenario, number> = {
      blowout_loss: 8,
      bad_beat: 2,
      upset_loss: 9,
      blown_lead: 7,
      plain_loss: 11,
      upset_win: 12,
      backdoor_win: 12,
      dominant_win: 12,
      plain_win: 12,
      push: 5,
    };
    for (const scenario of SCENARIOS) {
      for (const pickMode of ["ats", "straightUp"] as const) {
        for (const hook of [false, true]) {
          const lines = renderScenarioLines(scenario, { ...longNames, pickMode }, { hook });
          const size =
            scenario === "bad_beat" && hook && pickMode === "ats" ? 1 : expected[scenario];
          expect(lines.length, `${scenario} ${pickMode} hook=${hook}`).toBe(size);
          expect(new Set(lines).size, scenario).toBe(lines.length);
          for (const line of lines) {
            expect(line.length, line).toBeLessThanOrEqual(MAX_PUSH_BODY_LENGTH);
            expect(line.length, line).toBeGreaterThan(0);
            expect(line.includes("{"), line).toBe(false);
            expect(line.toLowerCase().includes("better luck")).toBe(false);
          }
        }
      }
    }
  });

  it("includes the group-chat lines and the scenario examples", () => {
    const losses = renderScenarioLines("plain_loss", longNames);
    expect(losses).toContain("Hope you didn't put money on that.");
    expect(losses).toContain("What were you thinking?");
    expect(losses).toContain("Horrible pick.");
    expect(losses).not.toContain("Tough beat if you're a liar. You just got it wrong.");

    expect(renderScenarioLines("upset_loss", game({ spread: 21 }))).toContain(
      "You took a 21-point favorite and they lost outright. Delete the app."
    );
    expect(renderScenarioLines("backdoor_win", game())).toContain(
      "Backdoor cover. You did nothing and still got paid."
    );
    expect(renderScenarioLines("backdoor_win", game({ pickMode: "straightUp" }))).not.toContain(
      "Backdoor cover. You did nothing and still got paid."
    );
    const hookLines = renderScenarioLines(
      "bad_beat",
      game({ spread: 6.5, homeScore: 27, awayScore: 21 }),
      { hook: true }
    );
    expect(hookLines).toEqual(["Half a point. Michigan sends their regards and the receipt."]);
    expect(hookLines).not.toContain("Missed by the hook. The football gods hate you specifically.");
    expect(renderScenarioLines("push", game())).toEqual(renderScenarioLines("push", game({ pickMode: "straightUp" })));
    expect(renderScenarioLines("push", game())).toHaveLength(5);
  });

  it("keeps titles short", () => {
    for (const scenario of SCENARIOS) {
      const copy = gameFinalPushCopy(inputFor(scenario));
      expect(copy.title.length, `${scenario} ${copy.title}`).toBeLessThanOrEqual(MAX_PUSH_TITLE_LENGTH);
      expect(copy.body.length).toBeLessThanOrEqual(MAX_PUSH_BODY_LENGTH);
    }
  });
});

describe("deterministic selection", () => {
  it("repeats the same line for the same user and game", () => {
    const input = game({ spread: 3, homeScore: 10, awayScore: 31 });
    expect(gameFinalPushCopy(input)).toEqual(gameFinalPushCopy(input));
    expect(stableHash("user-1:game-1")).toBe(stableHash("user-1:game-1"));
  });

  it("skips the previous body for a new game and reuses it on a retry of the same game", () => {
    const input = game({ spread: 21, homeScore: 10, awayScore: 24 });
    const natural = gameFinalPushCopy({ ...input, gameId: "g2" });
    const avoided = gameFinalPushCopy({
      ...input,
      gameId: "g2",
      previous: { key: "group-1:g1", title: natural.title, body: natural.body },
    });
    expect(avoided.body).not.toBe(natural.body);
    expect(avoided.title).toBe(natural.title);

    const retry = gameFinalPushCopy({
      ...input,
      previous: { key: "group-1:game-1", title: "Kept", body: "Stored roast." },
    });
    expect(retry).toEqual({ title: "Kept", body: "Stored roast." });
  });

  it("falls back once when the only hook line is the previous body", () => {
    const hookLine = "Half a point. Michigan sends their regards and the receipt.";
    const input = game({ spread: 6.5, homeScore: 27, awayScore: 21, gameId: "g-hook" });
    const copy = gameFinalPushCopy({
      ...input,
      previous: { key: "group-1:other", title: "So close", body: hookLine },
    });
    expect(copy.title).toBe("So close");
    expect(copy.body).not.toBe(hookLine);
    expect([
      "Ohio State missed by half a point. Brutal.",
      "Short by half a point. Hang the screenshot in the group chat.",
    ]).toContain(copy.body);

    const again = gameFinalPushCopy({
      ...input,
      previous: { key: "group-1:other", title: "So close", body: hookLine },
    });
    expect(again).toEqual(copy);
  });

  it("does not let a stored roast replace plain copy", () => {
    const plain = gameFinalPushCopy(
      game({
        spicyAlerts: false,
        spread: 21,
        homeScore: 10,
        awayScore: 24,
        previous: { key: "group-1:game-1", title: "Kept", body: "Stored roast." },
      })
    );
    expect(plain).toEqual({ title: "Tough beat", body: "MICH @ OSU is final." });
  });
});

describe("spicyAlerts preference", () => {
  it("defaults on and lets a member boolean override the account", () => {
    expect(resolveSpicyAlerts(undefined, undefined)).toBe(true);
    expect(resolveSpicyAlerts({}, {})).toBe(true);
    expect(resolveSpicyAlerts({ spicyAlerts: "yes" as unknown as boolean })).toBe(true);
    expect(resolveSpicyAlerts({ spicyAlerts: false })).toBe(false);
    expect(resolveSpicyAlerts({ spicyAlerts: true }, { spicyAlerts: false })).toBe(false);
    expect(resolveSpicyAlerts({ spicyAlerts: false }, { spicyAlerts: true })).toBe(true);
    expect(resolveSpicyAlerts({ spicyAlerts: false }, { spicyAlerts: "no" })).toBe(false);
  });

  it("reads the last line off the user doc", () => {
    expect(readLastSpicyGameFinal(undefined)).toBeNull();
    expect(
      readLastSpicyGameFinal({
        lastSpicyGameFinalKey: "g:1",
        lastSpicyGameFinalTitle: "Upset",
        lastSpicyGameFinalBody: "Delete the app.",
      })
    ).toEqual({ key: "g:1", title: "Upset", body: "Delete the app." });
    expect(readLastSpicyGameFinal({ lastSpicyGameFinalKey: "g:1" })).toBeNull();
  });
});

describe("stored period fields", () => {
  it("reads the linescore aliases a game doc might carry", () => {
    expect(
      periodInputFromGame({
        homeLinescores: [7, 0],
        awayLineScores: [0, 7],
        homeHalftimeScore: 7,
        awayHalftimeScore: 7,
        homeScoreAfterThree: 14,
        awayScoreAfterThree: 10,
      })
    ).toEqual({
      homeLineScores: [7, 0],
      awayLineScores: [0, 7],
      halftimeHomeScore: 7,
      halftimeAwayScore: 7,
      afterThreeHomeScore: 14,
      afterThreeAwayScore: 10,
    });

    expect(periodInputFromGame({ linescores: { home: [3, 3], away: [0, 7] } })).toMatchObject({
      homeLineScores: [3, 3],
      awayLineScores: [0, 7],
    });
  });
});

function inputFor(scenario: GameFinalScenario): GameFinalCopyInput {
  switch (scenario) {
    case "blowout_loss":
      return game({ spread: 3, homeScore: 10, awayScore: 31 });
    case "bad_beat":
      return game({ spread: 6.5, homeScore: 27, awayScore: 21 });
    case "upset_loss":
      return game({ spread: 21, homeScore: 10, awayScore: 24 });
    case "blown_lead":
      return game({
        spread: 3,
        homeScore: 20,
        awayScore: 24,
        homeLineScores: [14, 7, 0, 0],
        awayLineScores: [0, 0, 10, 14],
      });
    case "plain_loss":
      return game({ spread: 7, homeScore: 24, awayScore: 21 });
    case "upset_win":
      return game({ pickedTeamId: "away", spread: 10, spreadTeamId: "home", homeScore: 17, awayScore: 21 });
    case "backdoor_win":
      return game({ spread: 3, homeScore: 24, awayScore: 20 });
    case "dominant_win":
      return game({ spread: 3, homeScore: 42, awayScore: 7 });
    case "plain_win":
      return game({ spread: 3, homeScore: 31, awayScore: 21 });
    case "push":
      return game({ spread: 7, homeScore: 28, awayScore: 21 });
  }
}
