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
  joinedAt?: unknown;
}

export interface PickDoc {
  userId: string;
  displayName: string;
  picks: Record<string, string>;
  isLocked?: boolean;
  confidenceGameId?: string | null;
  submittedAt?: unknown;
}

export type PickMode = "ats" | "straightUp";

export function resolvePickMode(value: unknown): PickMode {
  return value === "straightUp" ? "straightUp" : "ats";
}

/** Prefer a week snapshot so a mid-season group switch cannot regrade a locked week. */
export function weekPickMode(weekPickMode: unknown, groupPickMode: unknown): PickMode {
  return weekPickMode === "straightUp" || weekPickMode === "ats"
    ? weekPickMode
    : resolvePickMode(groupPickMode);
}

function weekSkipsSelection(week: {
  status?: unknown;
  slateSource?: unknown;
  weekNumber?: unknown;
}): boolean {
  return week.weekNumber === 0 || week.slateSource === "fixedBoard";
}

/** Open Selection weeks follow a commissioner type switch. Fixed slates wait until next week. */
export function shouldRewriteWeekPickMode(week: {
  status?: unknown;
  slateSource?: unknown;
  weekNumber?: unknown;
}): boolean {
  if (weekSkipsSelection(week)) return false;
  return week.status === "selection";
}

/** `null` means leave the week document alone. */
export function pickModeToPersistOnWeek(
  week: {
    status?: unknown;
    slateSource?: unknown;
    weekNumber?: unknown;
    pickMode?: unknown;
  },
  newMode: PickMode,
  previousMode: PickMode,
  pickModeChanged: boolean
): PickMode | null {
  if (shouldRewriteWeekPickMode(week)) {
    const current =
      week.pickMode === "straightUp" || week.pickMode === "ats" ? week.pickMode : null;
    return current === newMode ? null : newMode;
  }
  if (pickModeChanged && week.pickMode !== "ats" && week.pickMode !== "straightUp") {
    return previousMode;
  }
  return null;
}

export function pickModeSnapshotsForWeeks(
  weeks: Array<{
    id: string;
    status?: unknown;
    slateSource?: unknown;
    weekNumber?: unknown;
    pickMode?: unknown;
  }>,
  newMode: PickMode,
  previousMode: PickMode
): Array<{ id: string; pickMode: PickMode }> {
  const out: Array<{ id: string; pickMode: PickMode }> = [];
  for (const week of weeks) {
    const next = pickModeToPersistOnWeek(week, newMode, previousMode, true);
    if (next) out.push({ id: week.id, pickMode: next });
  }
  return out;
}

/** Keep scoring on `groups.memberIds` so leftover member docs cannot stay on the board. */
export function membersOnRoster<T extends { id: string }>(
  members: T[],
  memberIds: string[] | undefined
): T[] {
  if (!memberIds || memberIds.length === 0) return members;
  const allowed = new Set(memberIds);
  return members.filter((member) => allowed.has(member.id));
}

export function toMillis(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value === "object" && typeof (value as { toMillis?: unknown }).toMillis === "function") {
    const ms = (value as { toMillis: () => number }).toMillis();
    return Number.isFinite(ms) ? ms : null;
  }
  return null;
}

export function applyLatePickPenalty(
  scored: { wins: number; losses: number; pushes: number },
  options: {
    allowLatePicks?: boolean;
    latePickPenaltyWins?: number;
    submittedAt?: unknown;
    deadline?: unknown;
  }
): { wins: number; losses: number; pushes: number } {
  if (!options.allowLatePicks) return scored;
  const penalty = Math.max(0, options.latePickPenaltyWins ?? 0);
  if (penalty === 0) return scored;
  const submittedAtMs = toMillis(options.submittedAt);
  const deadlineMs = toMillis(options.deadline);
  if (submittedAtMs == null || deadlineMs == null) return scored;
  if (submittedAtMs <= deadlineMs) return scored;
  return { ...scored, wins: Math.max(0, scored.wins - penalty) };
}

export function coveredTeamId(
  game: SlateGameDoc,
  homeScore: number,
  awayScore: number,
  pickMode: PickMode = "ats"
): string | null {
  if (pickMode === "straightUp") {
    if (homeScore === awayScore) return null;
    return homeScore > awayScore ? game.homeTeamId : game.awayTeamId;
  }
  const spreadMagnitude = Math.abs(game.spread);
  const margin = homeScore - awayScore;
  const adjusted =
    margin + (game.spreadTeamId === game.homeTeamId ? -spreadMagnitude : spreadMagnitude);
  if (adjusted === 0) return null;
  return adjusted > 0 ? game.homeTeamId : game.awayTeamId;
}

/** Heartbreaker near-miss. ATS uses cover margin vs the line; Straight Up uses raw score. */
export function nearMissMargin(
  game: SlateGameDoc,
  homeScore: number,
  awayScore: number,
  pickMode: PickMode = "ats"
): number {
  if (pickMode === "straightUp") return Math.abs(homeScore - awayScore);
  return Math.abs(
    homeScore -
      awayScore +
      (game.spreadTeamId === game.homeTeamId ? -Math.abs(game.spread) : Math.abs(game.spread))
  );
}

/** True when the user actually chose a team for this slate game. */
export function pickedTeamId(picks: Record<string, string>, gameId: string): string | null {
  const picked = picks[gameId];
  if (typeof picked !== "string") return null;
  const trimmed = picked.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/** Week 0 docs are `{seasonYear}-W0` with `weekNumber: 0`. */
export function isWeekZero(weekId: string, weekNumber?: unknown): boolean {
  if (weekNumber === 0) return true;
  return /(^|-)W0$/i.test(weekId);
}

/**
 * Admin rescore re-sums every scored week. Keep Week 0 on skip-miss math unless
 * Week 0 itself is the week being rescored (which we do not do in production).
 */
export function missedPickIsLossForSeasonWeek(options: {
  targetWeekId: string;
  targetWeekNumber?: unknown;
  seasonWeekId: string;
  seasonWeekNumber?: unknown;
}): boolean {
  if (isWeekZero(options.targetWeekId, options.targetWeekNumber)) return true;
  if (isWeekZero(options.seasonWeekId, options.seasonWeekNumber)) return false;
  return true;
}

/**
 * Score a member against the slate. Keep in sync with iOS `ScoringEngine.scorePicks`.
 * A final slate game with no Pickem is an automatic loss (weight 1, even on a push
 * or if it was marked as the confidence game).
 *
 * Pass `missedPickIsLoss: false` only when re-summing historical Week 0 so a later
 * week's admin rescore does not rewrite Week 0's original skip-miss math.
 */
export function scorePicks(
  picks: Record<string, string>,
  games: SlateGameDoc[],
  confidenceGameId?: string | null,
  options?: { missedPickIsLoss?: boolean; pickMode?: PickMode }
): { wins: number; losses: number; pushes: number } {
  const missedPickIsLoss = options?.missedPickIsLoss !== false;
  const pickMode = resolvePickMode(options?.pickMode);
  let wins = 0;
  let losses = 0;
  let pushes = 0;
  for (const game of games) {
    if (game.status !== "final" || game.homeScore == null || game.awayScore == null) continue;
    const picked = pickedTeamId(picks, game.id);
    if (!picked) {
      if (missedPickIsLoss) losses += 1;
      continue;
    }
    const covered = coveredTeamId(game, game.homeScore, game.awayScore, pickMode);
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

/** Rank by most weekly wins, then name. Keep in sync with iOS `ScoringEngine.rankedStandings`. */
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
  // Rank by most wins outright — not batting average. Keep in sync with iOS
  // `ScoringEngine.rankedStandings`. Same win totals share a rank.
  const sorted = [...entries].sort((a, b) => {
    if (b.weeklyWins !== a.weeklyWins) return b.weeklyWins - a.weeklyWins;
    return a.displayName.localeCompare(b.displayName);
  });

  return sorted.map((entry, index) => {
    const prev = sorted[index - 1];
    const tied = !!prev && prev.weeklyWins === entry.weeklyWins;
    const rank = tied
      ? sorted.findIndex((e) => e.weeklyWins === entry.weeklyWins) + 1
      : index + 1;
    return { ...entry, rank, isTied: tied };
  });
}

export function computeWeekAwards(
  picks: PickDoc[],
  games: SlateGameDoc[],
  pickMode: PickMode = "ats"
): {
  sharpshooterUserId?: string;
  heartbreakerUserId?: string;
  contrarianUserId?: string;
} {
  if (picks.length === 0 || games.length === 0) return {};
  const mode = resolvePickMode(pickMode);

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
    const scored = scorePicks(pick.picks, games, pick.confidenceGameId, { pickMode: mode });
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
      const covered = coveredTeamId(game, game.homeScore, game.awayScore, mode);
      if (covered == null) continue;
      if (covered !== picked) {
        if (nearMissMargin(game, game.homeScore, game.awayScore, mode) <= 3) nearMisses += 1;
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
