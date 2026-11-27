/** ESPN scoreboard fetch planning for `lockAndScoreWeeks`. */

import type { EspnEvent } from "./espn";
import { espnScoreboardWeek } from "./cfbWeekCalendar";
import {
  BOWL_SEASON_TYPE,
  ESPN_BOWL2_POSTSEASON_WEEK,
  ESPN_POSTSEASON_WEEK,
  isBowlWeekId,
  parseBowlWeekId,
} from "./bowlWeek";
export { bowlWeekCatalogEvents } from "./bowlCatalogPartition";

export type ScoreboardFetchTarget = { week?: number; seasonType: number };

export function postseasonEspnWeeksForWeekDocs(
  weekDocs: Array<{ id: string; data: Record<string, unknown> }>
): Set<number> {
  const weeks = new Set<number>();
  for (const doc of weekDocs) {
    const bowl =
      isBowlWeekId(doc.id) ||
      (doc.data.seasonType as number | undefined) === BOWL_SEASON_TYPE;
    if (!bowl) continue;
    const parsed = parseBowlWeekId(doc.id);
    if (parsed?.slot === "BOWL2") {
      weeks.add(ESPN_POSTSEASON_WEEK);
      weeks.add(ESPN_BOWL2_POSTSEASON_WEEK);
    } else {
      weeks.add(ESPN_POSTSEASON_WEEK);
    }
  }
  return weeks;
}

export function buildScoreboardFetchTargets(
  weekNumbers: Iterable<number>,
  postseasonEspnWeeks: Iterable<number>
): ScoreboardFetchTarget[] {
  const weeks = [...new Set([...weekNumbers].map((n) => espnScoreboardWeek(n)))]
    .filter((n) => Number.isFinite(n) && n > 0);
  const targets: ScoreboardFetchTarget[] =
    weeks.length === 0 ? [{ seasonType: 2 }] : weeks.map((week) => ({ week, seasonType: 2 }));
  for (const week of [...new Set(postseasonEspnWeeks)].filter((n) => Number.isFinite(n) && n > 0)) {
    targets.push({ week, seasonType: BOWL_SEASON_TYPE });
  }
  return targets;
}
