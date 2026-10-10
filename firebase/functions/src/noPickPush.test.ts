import { describe, expect, it } from "vitest";
import {
  NO_PICK_MULTI_TEMPLATES,
  NO_PICK_SINGLE_TEMPLATES,
  notifiedNoPickGameIds,
  planNoPickPush,
  type NoPickGame,
  type NoPickPlanInput,
} from "./noPickPush";

function game(overrides: Partial<NoPickGame> = {}): NoPickGame {
  return {
    id: "g1",
    locked: true,
    away: "MICH",
    home: "OSU",
    score: "MICH 21, OSU 24",
    ...overrides,
  };
}

function input(overrides: Partial<NoPickPlanInput> = {}): NoPickPlanInput {
  return {
    weekStatus: "locked",
    games: [game()],
    userId: "user-1",
    picks: {},
    wantsGameFinals: true,
    spicyAlerts: true,
    alreadyNotifiedGameIds: [],
    ...overrides,
  };
}

const SINGLE = [
  "You didn't pick MICH @ OSU. That's a loss. Bold strategy.",
  "No pick, no points. MICH 21, OSU 24.",
  "Forgot to pick? The loss column didn't.",
  "MICH @ OSU is final. You weren't even in the building.",
  "Zero effort, one loss. Set an alarm next week.",
  "Missed the pick. The group chat noticed.",
];

describe("planNoPickPush", () => {
  it("sends one spicy line for a single missed locked game", () => {
    const plan = planNoPickPush(input());
    expect(plan).toMatchObject({ userId: "user-1", gameIds: ["g1"], title: "No pick" });
    expect(SINGLE).toContain(plan?.body);
    expect(planNoPickPush(input())).toEqual(plan);
    expect(plan?.body.length).toBeLessThanOrEqual(120);
    expect(NO_PICK_SINGLE_TEMPLATES).toHaveLength(6);
  });

  it("combines several misses from the same run into one push", () => {
    const plan = planNoPickPush(
      input({
        games: [game({ id: "g2" }), game({ id: "g1", away: "PSU", home: "IOWA" })],
      })
    );
    expect(plan?.gameIds).toEqual(["g1", "g2"]);
    expect(plan?.title).toBe("No pick");
    expect([
      "No pick on 2 games. That's 2 losses. Impressive commitment to nothing.",
      "2 games, zero picks. The loss column says thanks.",
    ]).toContain(plan?.body);
    expect(NO_PICK_MULTI_TEMPLATES).toHaveLength(2);
  });

  it("does not send a game that was already notified, including a partial set", () => {
    expect(planNoPickPush(input({ alreadyNotifiedGameIds: ["g1"] }))).toBeNull();
    const partial = planNoPickPush(
      input({
        games: [game(), game({ id: "g2" })],
        alreadyNotifiedGameIds: ["g1"],
      })
    );
    expect(partial?.gameIds).toEqual(["g2"]);
    expect(partial?.body ?? "").not.toContain("games");
    expect(SINGLE).toContain(partial?.body);
  });

  it("ignores an unlocked game and a pick that is only whitespace", () => {
    expect(planNoPickPush(input({ games: [game({ locked: false })] }))).toBeNull();
    expect(
      planNoPickPush(
        input({
          games: [game({ locked: false }), game({ id: "g2" })],
        })
      )?.gameIds
    ).toEqual(["g2"]);
    const blank = planNoPickPush(input({ picks: { g1: "   " } }));
    expect(blank?.gameIds).toEqual(["g1"]);
    expect(planNoPickPush(input({ picks: { g1: "home" } }))).toBeNull();
    expect(
      planNoPickPush(
        input({
          games: [game(), game({ id: "g2" })],
          picks: { g1: "home" },
        })
      )?.gameIds
    ).toEqual(["g2"]);
  });

  it("sends the plain sentence when spicy alerts are off", () => {
    expect(planNoPickPush(input({ spicyAlerts: false }))).toEqual({
      userId: "user-1",
      gameIds: ["g1"],
      title: "No pick",
      body: "MICH @ OSU is final. No pick counts as a loss.",
    });
    expect(
      planNoPickPush(
        input({
          spicyAlerts: false,
          games: [game(), game({ id: "g2" })],
        })
      )?.body
    ).toBe("No pick on 2 games. That's 2 losses.");
  });

  it("skips when game-final notifications are off", () => {
    expect(planNoPickPush(input({ wantsGameFinals: false }))).toBeNull();
    expect(
      planNoPickPush(
        input({
          wantsGameFinals: false,
          games: [game(), game({ id: "g2" })],
        })
      )
    ).toBeNull();
  });

  it("skips weeks that are not in Pickems or locked, and drops a score-less spicy line", () => {
    expect(planNoPickPush(input({ weekStatus: "scored" }))).toBeNull();
    expect(planNoPickPush(input({ weekStatus: "selection" }))).toBeNull();
    expect(planNoPickPush(input({ weekStatus: "picking" }))?.gameIds).toEqual(["g1"]);

    const quiet = planNoPickPush(input({ games: [game({ score: null })] }));
    expect(quiet?.body).not.toBe("No pick, no points. .");
    expect(quiet?.body.includes("{")).toBe(false);
    expect(SINGLE.filter((line) => !line.includes("MICH 21"))).toContain(quiet?.body);
  });
});

describe("notifiedNoPickGameIds", () => {
  it("reads the marker and ignores junk", () => {
    expect(notifiedNoPickGameIds(undefined)).toEqual([]);
    expect(notifiedNoPickGameIds({ gameIds: ["g1", "", 4, "g2"] })).toEqual(["g1", "g2"]);
  });
});
