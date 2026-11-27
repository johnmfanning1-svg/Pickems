import { describe, expect, it } from "vitest";
import type { EspnEvent } from "./espn";
import {
  BOWL_SEASON_TYPE,
  ESPN_BOWL2_POSTSEASON_WEEK,
  ESPN_POSTSEASON_WEEK,
} from "./bowlWeek";
import {
  bowlWeekCatalogEvents,
  buildScoreboardFetchTargets,
  postseasonEspnWeeksForWeekDocs,
} from "./scoreboardLoad";

describe("scoreboardLoad", () => {
  it("requests ESPN postseason weeks 1 and 999 when both bowl weeks are active", () => {
    const docs = [
      { id: "2026-BOWL1", data: { status: "locked", seasonType: BOWL_SEASON_TYPE } },
      { id: "2026-BOWL2", data: { status: "picking", seasonType: BOWL_SEASON_TYPE } },
    ];
    expect(postseasonEspnWeeksForWeekDocs(docs)).toEqual(
      new Set([ESPN_POSTSEASON_WEEK, ESPN_BOWL2_POSTSEASON_WEEK])
    );
    const targets = buildScoreboardFetchTargets([15], postseasonEspnWeeksForWeekDocs(docs));
    expect(targets).toContainEqual({ week: ESPN_POSTSEASON_WEEK, seasonType: BOWL_SEASON_TYPE });
    expect(targets).toContainEqual({ week: ESPN_BOWL2_POSTSEASON_WEEK, seasonType: BOWL_SEASON_TYPE });
  });

  it("routes BOWL2 catalog and scoring to postseason week 999 events", () => {
    const titleGameId = "cfp-title-999";
    const earlyBowlId = "bowl-dec-20";
    const postseasonByEspnWeek = new Map<number, EspnEvent[]>([
      [ESPN_POSTSEASON_WEEK, [{ id: earlyBowlId } as EspnEvent]],
      [ESPN_BOWL2_POSTSEASON_WEEK, [{ id: titleGameId } as EspnEvent]],
    ]);
    const bowl1 = bowlWeekCatalogEvents(
      "2026-BOWL1",
      { seasonType: BOWL_SEASON_TYPE },
      postseasonByEspnWeek
    );
    const bowl2 = bowlWeekCatalogEvents(
      "2026-BOWL2",
      { seasonType: BOWL_SEASON_TYPE },
      postseasonByEspnWeek
    );
    expect(bowl1.map((e) => e.id)).toEqual([earlyBowlId]);
    expect(bowl2.map((e) => e.id)).toEqual([titleGameId]);
    const merged = new Map<string, EspnEvent>();
    for (const events of postseasonByEspnWeek.values()) {
      for (const event of events) merged.set(event.id, event);
    }
    expect(merged.get(titleGameId)?.id).toBe(titleGameId);
  });
});