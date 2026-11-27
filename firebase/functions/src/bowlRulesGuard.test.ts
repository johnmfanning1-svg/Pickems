import { describe, expect, it, vi } from "vitest";
import { revertBowlStandingsToggleIfLocked } from "./bowlRulesGuard";
import { COUNTS_TOWARD_SEASON_AT_SCORE } from "./bowlStandingsStamp";

function mockDb(scoredBowls: Array<{ id: string; stamp?: boolean }>) {
  const update = vi.fn();
  const batchUpdate = vi.fn();
  return {
    db: {
      collection: () => ({
        doc: () => ({
          collection: () => ({
            get: async () => ({
              docs: scoredBowls.map((bowl) => ({
                id: bowl.id,
                ref: { path: bowl.id },
                data: () => ({
                  status: "scored",
                  ...(bowl.stamp !== undefined
                    ? { [COUNTS_TOWARD_SEASON_AT_SCORE]: bowl.stamp }
                    : {}),
                }),
              })),
            }),
          }),
        }),
      }),
      batch: () => ({ update: batchUpdate, commit: async () => {} }),
    },
    update,
    batchUpdate,
  };
}

describe("bowlRulesGuard", () => {
  it("reverts countsTowardSeasonStandings when flip disagrees with stamped value", async () => {
    const { db, update } = mockDb([{ id: "2026-BOWL1", stamp: false }]);
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

  it("no-ops when after already matches stamped value (guard revert re-trigger)", async () => {
    const { db, update } = mockDb([{ id: "2026-BOWL1", stamp: false }]);
    const before = { rules: { bowlSeason: { countsTowardSeasonStandings: true } } };
    const after = { rules: { bowlSeason: { countsTowardSeasonStandings: false } } };
    const reverted = await revertBowlStandingsToggleIfLocked(
      db as never,
      "g1",
      before,
      after,
      { update } as never
    );
    expect(reverted).toBe(false);
    expect(update).not.toHaveBeenCalled();
  });
});