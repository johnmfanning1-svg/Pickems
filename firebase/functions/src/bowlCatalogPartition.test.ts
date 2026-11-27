import { describe, expect, it } from "vitest";
import type { EspnEvent } from "./espn";
import { ESPN_BOWL2_POSTSEASON_WEEK, ESPN_POSTSEASON_WEEK } from "./bowlWeek";
import { bowlWeekCatalogEvents } from "./bowlCatalogPartition";
import { bowl1CatalogEndExclusiveMs, postseasonCatalogOpensMs } from "./bowlWeek";

function event(id: string, kickoffMs: number): EspnEvent {
  return { id, date: new Date(kickoffMs).toISOString() };
}

describe("bowlCatalogPartition", () => {
  it("assigns every postseason event to exactly one bowl slot", () => {
    const opens = postseasonCatalogOpensMs();
    const cutoff = bowl1CatalogEndExclusiveMs();
    const postseasonByEspnWeek = new Map<number, EspnEvent[]>([
      [
        ESPN_POSTSEASON_WEEK,
        [
          event("early", opens + 86_400_000),
          event("late-jan", cutoff + 86_400_000),
        ],
      ],
      [ESPN_BOWL2_POSTSEASON_WEEK, [event("cfp", cutoff + 2 * 86_400_000)]],
    ]);
    const bowl1 = bowlWeekCatalogEvents("2026-BOWL1", { seasonType: 3 }, postseasonByEspnWeek);
    const bowl2 = bowlWeekCatalogEvents("2026-BOWL2", { seasonType: 3 }, postseasonByEspnWeek);
    const ids1 = new Set(bowl1.map((e) => e.id));
    const ids2 = new Set(bowl2.map((e) => e.id));
    expect(ids1).toEqual(new Set(["early"]));
    expect(ids2).toEqual(new Set(["late-jan", "cfp"]));
    const all = new Set([...ids1, ...ids2]);
    expect(all).toEqual(new Set(["early", "late-jan", "cfp"]));
    expect([...ids1].some((id) => ids2.has(id))).toBe(false);
  });
});