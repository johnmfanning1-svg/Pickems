/** How scored weeks contribute to `seasonWins` vs `bowlWins` when toggling bowl standings. */

import { bowlCountsTowardSeason, isBowlWeekId } from "./bowlWeek";
import { bowlWeekCountsTowardSeason } from "./bowlStandingsStamp";

export type ScoredWeekInput = {
  weekId: string;
  seasonType?: number;
  countsTowardSeasonStandingsAtScore?: boolean;
};

export type MemberScore = { wins: number; losses: number };

export function accumulateMemberTotals(
  rules: { bowlSeason?: { countsTowardSeasonStandings?: boolean } | null },
  scoredWeeks: ScoredWeekInput[],
  scoreByWeekMember: Map<string, Map<string, MemberScore>>
): { season: Map<string, MemberScore>; bowl: Map<string, MemberScore> } {
  const season = new Map<string, MemberScore>();
  const bowl = new Map<string, MemberScore>();
  for (const week of scoredWeeks) {
    const bowlWeek = isBowlWeekId(week.weekId);
    const memberScores = scoreByWeekMember.get(week.weekId);
    if (!memberScores) continue;
    const towardSeason = bowlWeek
      ? bowlWeekCountsTowardSeason(rules, week)
      : bowlCountsTowardSeason(rules);
    for (const [memberId, scored] of memberScores) {
      if (bowlWeek) {
        const running = bowl.get(memberId) ?? { wins: 0, losses: 0 };
        bowl.set(memberId, {
          wins: running.wins + scored.wins,
          losses: running.losses + scored.losses,
        });
      }
      if (!bowlWeek || towardSeason) {
        const running = season.get(memberId) ?? { wins: 0, losses: 0 };
        season.set(memberId, {
          wins: running.wins + scored.wins,
          losses: running.losses + scored.losses,
        });
      }
    }
  }
  return { season, bowl };
}

export function bowlStandingsToggleShouldLock(scoredWeekIds: string[]): boolean {
  return scoredWeekIds.some((id) => isBowlWeekId(id));
}