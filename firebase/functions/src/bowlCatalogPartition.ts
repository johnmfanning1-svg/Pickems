import type { EspnEvent } from "./espn";
import {
  ESPN_BOWL2_POSTSEASON_WEEK,
  ESPN_POSTSEASON_WEEK,
  parseBowlWeekId,
  postseasonEventBelongsToBowlSlot,
} from "./bowlWeek";

export function bowlWeekCatalogEvents(
  weekId: string,
  weekData: Record<string, unknown>,
  postseasonByEspnWeek: Map<number, EspnEvent[]>
): EspnEvent[] {
  const parsed = parseBowlWeekId(weekId);
  if (!parsed) return [];
  const seasonType = weekData.seasonType as number | undefined;
  if (seasonType != null && seasonType !== 3) return [];

  const week1 = postseasonByEspnWeek.get(ESPN_POSTSEASON_WEEK) ?? [];
  const week999 = postseasonByEspnWeek.get(ESPN_BOWL2_POSTSEASON_WEEK) ?? [];
  if (parsed.slot === "BOWL") {
    const fromWeek1 = week1.filter((event) =>
      postseasonEventBelongsToBowlSlot(event, "BOWL", ESPN_POSTSEASON_WEEK)
    );
    const from999 = week999.filter((event) =>
      postseasonEventBelongsToBowlSlot(event, "BOWL", ESPN_BOWL2_POSTSEASON_WEEK)
    );
    const seen = new Set<string>();
    return [...fromWeek1, ...from999].filter((event) => {
      if (seen.has(event.id)) return false;
      seen.add(event.id);
      return true;
    });
  }
  const fromWeek1 = week1.filter((event) =>
    postseasonEventBelongsToBowlSlot(event, parsed.slot, ESPN_POSTSEASON_WEEK)
  );
  if (parsed.slot === "BOWL2") {
    const from999 = week999.filter((event) =>
      postseasonEventBelongsToBowlSlot(event, "BOWL2", ESPN_BOWL2_POSTSEASON_WEEK)
    );
    return [...fromWeek1, ...from999];
  }
  return fromWeek1;
}