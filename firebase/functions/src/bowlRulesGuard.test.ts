import { describe, expect, it, vi } from "vitest";
import { revertBowlStandingsToggleIfLocked } from "./bowlRulesGuard";

describe("bowlRulesGuard", () => {
  it("reverts countsTowardSeasonStandings when a bowl week is already scored", async () => {
    const update = vi.fn();
    const db = {
      collection: () => ({
        doc: () => ({
          collection: () => ({
            get: async () => ({
              docs: [{ id: "2026-BOWL1", data: () => ({ status: "scored" }) }],
            }),
          }),
        }),
      }),
    };
    const before = { rules: { bowlSeason: { countsTowardSeasonStandings: false } } };
    const after = { rules: { bowlSeason: { countsTowardSeasonStandings: true } } };
    const reverted = await revertBowlStandingsToggleIfLocked(
      db as never,
      "g1",
      before,
      after,
      { update } as never
    );
    expect(reverted).toBe(true);
    expect(update).toHaveBeenCalledWith({
      "rules.bowlSeason.countsTowardSeasonStandings": false,
    });
  });
});