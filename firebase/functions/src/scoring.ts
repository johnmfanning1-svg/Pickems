export interface SlateGameDoc {
  id: string;
  espnEventId: string;
  homeTeamId: string;
  awayTeamId: string;
  homeTeamName?: string;
  awayTeamName?: string;
  homeTeamAbbreviation?: string;
  awayTeamAbbreviation?: string;
  spread: number;
  spreadTeamId: string;
  status: "scheduled" | "inProgress" | "final";
  homeScore?: number | null;
  awayScore?: number | null;
  winnerTeamId?: string | null;
}

export interface MemberDoc {
  id: string;
  displayName: string;
  avatarColorHex: string;
  seasonWins: number;
  seasonLosses: number;
}

export interface PickDoc {
  userId: string;
  displayName: string;
  picks: Record<string, string>;
  isLocked?: boolean;
  confidenceGameId?: string | null;
}

export function coveredTeamId(
  game: SlateGameDoc,
  homeScore: number,
  awayScore: number
): string | null {
  const spreadMagnitude = Math.abs(game.spread);
  const margin = homeScore - awayScore;
  const adjusted =
    margin + (game.spreadTeamId === game.homeTeamId ? -spreadMagnitude : spreadMagnitude);
  if (adjusted === 0) return null;
  return adjusted > 0 ? game.homeTeamId : game.awayTeamId;
}

export function scorePicks(
  picks: Record<string, string>,
  games: SlateGameDoc[],
  confidenceGameId?: string | null
): { wins: number; losses: number; pushes: number } {
  let wins = 0;
  let losses = 0;
  let pushes = 0;
  for (const game of games) {
    if (game.status !== "final" || game.homeScore == null || game.awayScore == null) continue;
    const picked = picks[game.id];
    if (!picked) continue;
    const covered = coveredTeamId(game, game.homeScore, game.awayScore);
    const weight = confidenceGameId && confidenceGameId === game.id ? 2 : 1;
    if (covered == null) {
      pushes += 1;
    } else if (covered === picked) {
      wins += weight;
    } else {
      losses += weight;
    }
  }
  return { wins, losses, pushes };
}

export function rankEntries(
  entries: Array<{
    id: string;
    displayName: string;
    avatarColorHex: string;
    weeklyWins: number;
    weeklyLosses: number;
    seasonWins: number;
    seasonLosses: number;
  }>
): Array<{
  id: string;
  displayName: string;
  avatarColorHex: string;
  weeklyWins: number;
  weeklyLosses: number;
  seasonWins: number;
  seasonLosses: number;
  rank: number;
  isTied: boolean;
}> {
  const sorted = [...entries].sort((a, b) => {
    if (b.weeklyWins !== a.weeklyWins) return b.weeklyWins - a.weeklyWins;
    const aAvg = a.weeklyWins + a.weeklyLosses === 0 ? 0 : a.weeklyWins / (a.weeklyWins + a.weeklyLosses);
    const bAvg = b.weeklyWins + b.weeklyLosses === 0 ? 0 : b.weeklyWins / (b.weeklyWins + b.weeklyLosses);
    if (bAvg !== aAvg) return bAvg - aAvg;
    return a.displayName.localeCompare(b.displayName);
  });

  return sorted.map((entry, index) => {
    const prev = sorted[index - 1];
    const tied =
      !!prev &&
      prev.weeklyWins === entry.weeklyWins &&
      prev.weeklyLosses === entry.weeklyLosses;
    const rank = tied ? (sorted.findIndex((e) => e.weeklyWins === entry.weeklyWins && e.weeklyLosses === entry.weeklyLosses) + 1) : index + 1;
    return { ...entry, rank, isTied: tied };
  });
}

export function computeWeekAwards(
  picks: PickDoc[],
  games: SlateGameDoc[]
): {
  sharpshooterUserId?: string;
  heartbreakerUserId?: string;
  contrarianUserId?: string;
} {
  if (picks.length === 0 || games.length === 0) return {};

  let sharpshooterUserId: string | undefined;
  let bestWins = -1;
  let heartbreakerUserId: string | undefined;
  let mostNearMisses = -1;
  let contrarianUserId: string | undefined;
  let mostUnique = -1;

  const pickCounts: Record<string, Record<string, number>> = {};
  for (const game of games) {
    pickCounts[game.id] = {};
    for (const pick of picks) {
      const team = pick.picks[game.id];
      if (!team) continue;
      pickCounts[game.id][team] = (pickCounts[game.id][team] ?? 0) + 1;
    }
  }

  for (const pick of picks) {
    const scored = scorePicks(pick.picks, games, pick.confidenceGameId);
    if (scored.wins > bestWins) {
      bestWins = scored.wins;
      sharpshooterUserId = pick.userId;
    }

    let nearMisses = 0;
    let uniqueCorrect = 0;
    for (const game of games) {
      if (game.status !== "final" || game.homeScore == null || game.awayScore == null) continue;
      const picked = pick.picks[game.id];
      if (!picked) continue;
      const covered = coveredTeamId(game, game.homeScore, game.awayScore);
      if (covered == null) continue;
      if (covered !== picked) {
        const margin = Math.abs(
          game.homeScore -
            game.awayScore +
            (game.spreadTeamId === game.homeTeamId ? -Math.abs(game.spread) : Math.abs(game.spread))
        );
        if (margin <= 3) nearMisses += 1;
      } else if ((pickCounts[game.id]?.[picked] ?? 0) === 1) {
        uniqueCorrect += 1;
      }
    }
    if (nearMisses > mostNearMisses) {
      mostNearMisses = nearMisses;
      heartbreakerUserId = pick.userId;
    }
    if (uniqueCorrect > mostUnique) {
      mostUnique = uniqueCorrect;
      contrarianUserId = pick.userId;
    }
  }

  return { sharpshooterUserId, heartbreakerUserId, contrarianUserId };
}
