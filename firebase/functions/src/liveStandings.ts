/**
 * Decide whether `lockAndScoreWeeks` should rewrite `standings/current` with
 * live (in-progress) weekly tallies for an active week that is not fully final.
 *
 * - Rolling-lock weeks stay `picking` until the last kickoff, so finals that
 *   land while the week is still `picking` must refresh the board too
 *   (previously only `locked` weeks did, leaving last week's tallies up).
 * - Self-heal: if a game in this week is already final but the standings doc
 *   still points at an older week (e.g. a final landed before this fix, or the
 *   refresh pass failed), refresh even without a new final this pass. Only
 *   moves forward so two active weeks cannot ping-pong the doc.
 */
export function shouldRefreshLiveStandings(options: {
  weekStatus: unknown;
  weekNumber: unknown;
  anyFinalizedThisPass: boolean;
  anyGameFinal: boolean;
  standingsWeekNumber: unknown;
}): boolean {
  const { weekStatus, weekNumber, anyFinalizedThisPass, anyGameFinal, standingsWeekNumber } =
    options;
  if (weekStatus !== "picking" && weekStatus !== "locked") return false;
  if (!anyGameFinal) return false;
  if (anyFinalizedThisPass) return true;
  if (typeof weekNumber !== "number") return false;
  if (typeof standingsWeekNumber !== "number") return true;
  return standingsWeekNumber < weekNumber;
}
