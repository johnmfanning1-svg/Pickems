import { describe, it, expect } from "vitest";
import { shouldRefreshLiveStandings } from "./liveStandings";

const base = {
  weekStatus: "locked",
  weekNumber: 4,
  anyFinalizedThisPass: false,
  anyGameFinal: true,
  standingsWeekNumber: 4,
};

describe("shouldRefreshLiveStandings", () => {
  it("refreshes a locked week when a game finalizes this pass", () => {
    expect(shouldRefreshLiveStandings({ ...base, anyFinalizedThisPass: true })).toBe(true);
  });

  it("refreshes a rolling week still in picking when a game finalizes", () => {
    // PPP 2026-W4: Army @ Temple went final while the rolling week was `picking`.
    expect(
      shouldRefreshLiveStandings({
        ...base,
        weekStatus: "picking",
        anyFinalizedThisPass: true,
        standingsWeekNumber: 3,
      })
    ).toBe(true);
  });

  it("self-heals when standings still point at last week and a final exists", () => {
    expect(shouldRefreshLiveStandings({ ...base, standingsWeekNumber: 3 })).toBe(true);
    expect(shouldRefreshLiveStandings({ ...base, standingsWeekNumber: undefined })).toBe(true);
  });

  it("does not rewrite every pass once standings match this week", () => {
    expect(shouldRefreshLiveStandings(base)).toBe(false);
  });

  it("never moves standings backward to an older active week", () => {
    expect(shouldRefreshLiveStandings({ ...base, weekNumber: 3, standingsWeekNumber: 4 })).toBe(
      false
    );
  });

  it("skips weeks with no final games or inactive status", () => {
    expect(
      shouldRefreshLiveStandings({ ...base, anyGameFinal: false, standingsWeekNumber: 3 })
    ).toBe(false);
    expect(
      shouldRefreshLiveStandings({ ...base, weekStatus: "scored", anyFinalizedThisPass: true })
    ).toBe(false);
    expect(
      shouldRefreshLiveStandings({ ...base, weekStatus: "selection", standingsWeekNumber: 3 })
    ).toBe(false);
  });
});
