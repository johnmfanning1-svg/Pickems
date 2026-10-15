/**
 * Kickoffs for games a member can still swap onto during Selections.
 * `lockAndScoreWeeks` writes these onto `gameLock/current` before any slate
 * doc exists. The timestamp is ESPN's event date, never the client's.
 */
export function kickoffsMillisByEspnEventId(
  events: readonly { id?: string; date?: string }[]
): Record<string, number> {
  const kickoffs: Record<string, number> = {};
  for (const event of events) {
    const id = typeof event.id === "string" ? event.id.trim() : "";
    if (!id || typeof event.date !== "string" || event.date.trim() === "") continue;
    const ms = Date.parse(event.date);
    if (!Number.isFinite(ms)) continue;
    kickoffs[id] = ms;
  }
  return kickoffs;
}
