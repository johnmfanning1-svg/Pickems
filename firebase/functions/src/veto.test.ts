import { describe, expect, it, vi } from "vitest";

vi.mock("./notifications", () => ({ sendToUser: vi.fn() }));

import { buildVetoPush, planVeto, vetoThreshold, DEFAULT_VETO_VOTES_NEEDED } from "./veto";
import { shouldSendDeadlinePush } from "./deadlinePushPrefs";

const NOW = Date.UTC(2026, 9, 14, 16, 0, 0);
const HOUR = 60 * 60 * 1000;

function group(overrides: Record<string, unknown> = {}) {
  return {
    name: "Saturday Crew",
    memberIds: ["sel", "a", "b", "c"],
    rules: { allowVeto: true, vetoVotesNeeded: 2 },
    ...overrides,
  };
}

const week = { status: "selection", selectionDeadline: NOW + HOUR };
const nomination = { submittedBy: "sel", submitterName: "Sam", espnEventId: "401", kickoff: NOW + 2 * HOUR };

describe("vetoThreshold", () => {
  it("defaults to 2 and caps at league size minus one", () => {
    expect(DEFAULT_VETO_VOTES_NEEDED).toBe(2);
    expect(vetoThreshold(undefined, 6)).toBe(2);
    expect(vetoThreshold(9, 4)).toBe(3);
    expect(vetoThreshold(2, 2)).toBe(1);
    expect(vetoThreshold(0, 5)).toBe(1);
    expect(vetoThreshold(Number.NaN, 5)).toBe(2);
    expect(vetoThreshold(2.9, 5)).toBe(2);
  });
});

describe("planVeto", () => {
  const base = { nowMs: NOW, group: group(), week, nomination };

  it("waits below the threshold and removes at it", () => {
    expect(planVeto({ ...base, voterIds: ["a"] })).toEqual({ action: "wait", threshold: 2, voteCount: 1 });
    expect(planVeto({ ...base, voterIds: ["a", "b"] })).toEqual({ action: "remove", threshold: 2, voteCount: 2 });
  });

  it("never counts the selector or non-members", () => {
    expect(planVeto({ ...base, voterIds: ["a", "sel", "outsider"] })).toEqual({
      action: "wait",
      threshold: 2,
      voteCount: 1,
    });
  });

  it("does nothing when the setting is off", () => {
    expect(planVeto({ ...base, group: group({ rules: { allowVeto: false } }), voterIds: ["a", "b"] }).action).toBe(
      "ignore"
    );
    expect(planVeto({ ...base, group: group({ rules: {} }), voterIds: ["a", "b"] }).action).toBe("ignore");
  });

  it("does nothing once Selections close, the deadline passes, or the game kicks off", () => {
    const votes = ["a", "b"];
    expect(planVeto({ ...base, week: { status: "picking" }, voterIds: votes })).toEqual({
      action: "ignore",
      reason: "selections_closed",
    });
    expect(planVeto({ ...base, week: { status: "selection", selectionDeadline: NOW - 1 }, voterIds: votes })).toEqual({
      action: "ignore",
      reason: "selection_deadline_passed",
    });
    expect(planVeto({ ...base, nomination: { ...nomination, kickoff: NOW - 1 }, voterIds: votes })).toEqual({
      action: "ignore",
      reason: "kickoff_passed",
    });
  });

  it("ignores a missing nomination (already vetoed or removed)", () => {
    expect(planVeto({ ...base, nomination: undefined, voterIds: ["a", "b"] }).action).toBe("ignore");
  });
});

describe("buildVetoPush", () => {
  const input = {
    leagueName: "Saturday Crew",
    groupId: "g1",
    weekId: "2026-W8",
    gameId: "401",
    matchup: { away: "UGA", home: "BAMA" },
    selectorName: "Sam",
  };

  it("names the game and league and deep-links to that game in that league", () => {
    const push = buildVetoPush({ ...input, isSelector: false });
    expect(push.title).toBe("Selection vetoed");
    expect(push.body).toContain("Saturday Crew");
    expect(push.body).toContain("UGA @ BAMA");
    expect(push.body).toContain("Sam");
    expect(push.subtitle).toContain("Saturday Crew");
    expect(push.data.deepLink).toBe("pickems://league/g1/week/2026-W8/game/401");
    expect(push.data).toMatchObject({ groupId: "g1", weekId: "2026-W8", gameId: "401" });
  });

  it("gives the selector their own copy", () => {
    const push = buildVetoPush({ ...input, isSelector: true });
    expect(push.title).toBe("Your Selection was vetoed");
    expect(push.body).toContain("Pick another game");
    expect(push.body).toContain("UGA @ BAMA");
    expect(push.body).toContain("Saturday Crew");
  });
});

describe("selection_veto push prefs", () => {
  it("follows the Selection deadlines switch", () => {
    expect(shouldSendDeadlinePush({}, "selection_veto")).toBe(true);
    expect(shouldSendDeadlinePush({ notifySelectionDeadlines: false }, "selection_veto")).toBe(false);
  });
});
