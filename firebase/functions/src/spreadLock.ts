import { isRollingLock, kickoffMillis } from "./pickLock";

/**
 * League spread lock. One line per game. It freezes and thaws with that game's
 * pick lock: week lock, the game's own kickoff, and its phase (pre / in / post).
 * `spread` is the league line. `lockedSpread` is the graded copy captured at
 * lock. `liveSpread` is ESPN movement and never grades.
 */

export interface WeekLockInput {
  status?: unknown;
  pickLockMode?: unknown;
  pickDeadline?: unknown;
  weekLockAt?: unknown;
  remainingLockAt?: unknown;
  /** Ignored for the week-level check. Per-game kickoff lives on the game. */
  allowLatePicks?: unknown;
}

export interface GameLockInput {
  id?: string;
  kickoff?: unknown;
  status?: unknown;
}

export type GamePhase = "pre" | "in" | "post";

/** ESPN `pre`/`in`/`post` and the stored `scheduled`/`inProgress`/`final` names. */
export function canonicalPhase(status: unknown): GamePhase {
  if (status === "in" || status === "inProgress") return "in";
  if (status === "post" || status === "final") return "post";
  return "pre";
}

/**
 * Games the pick rules should reject without a per-id phase map walk.
 * Kickoff time stays on `kickoffs` so rules can compare `request.time` exactly.
 * This list is only the non-pregame phase, which a timestamp compare would miss
 * when ESPN flips status before the stored kickoff.
 */
export function phaseLockedGameIds(games: Array<{ id?: unknown; status?: unknown }>): string[] {
  const ids: string[] = [];
  for (const game of games) {
    if (typeof game.id !== "string" || game.id.length === 0) continue;
    if (canonicalPhase(game.status) !== "pre") ids.push(game.id);
  }
  return ids;
}

export function isPregameStatus(status: unknown): boolean {
  if (status == null || status === "") return true;
  return canonicalPhase(status) === "pre";
}

/**
 * Week-level lock shared with pick selections.
 * A passed first-kickoff deadline locks the week. Late picks keep the week
 * open, but a started game stays locked via `gameEffectivelyLocked`.
 * Rolling weeks lock at `weekLockAt` / `remainingLockAt`, not at the first kickoff.
 */
export function weekLevelLocked(week: WeekLockInput, now: number): boolean {
  if (week.status === "locked" || week.status === "scored") return true;
  if (week.status === "selection") return false;
  const remaining = kickoffMillis(week.remainingLockAt);
  if (remaining != null && now >= remaining) return true;
  if (isRollingLock(week.pickLockMode)) {
    const weekLock = kickoffMillis(week.weekLockAt);
    return weekLock != null && now >= weekLock;
  }
  if (week.allowLatePicks === true) return false;
  const deadline = kickoffMillis(week.pickDeadline);
  return deadline != null && now >= deadline;
}

/**
 * A game is locked when the week is locked, its kickoff has passed, or it is
 * no longer pregame. Unlocking the week does not reopen a started game.
 */
export function gameEffectivelyLocked(
  week: WeekLockInput,
  game: GameLockInput,
  now: number
): boolean {
  if (weekLevelLocked(week, now)) return true;
  if (!isPregameStatus(game.status)) return true;
  const kick = kickoffMillis(game.kickoff);
  return kick != null && now >= kick;
}

export function hasLockedSpread(game: {
  lockedSpread?: unknown;
  lockedSpreadTeamId?: unknown;
}): boolean {
  return (
    typeof game.lockedSpread === "number" &&
    Number.isFinite(game.lockedSpread) &&
    typeof game.lockedSpreadTeamId === "string" &&
    game.lockedSpreadTeamId.length > 0
  );
}

/** Graded line. Legacy locked games with no snapshot fall back to `spread`. */
export function gradingLine(game: {
  spread?: unknown;
  spreadTeamId?: unknown;
  lockedSpread?: unknown;
  lockedSpreadTeamId?: unknown;
}): { spread: number; spreadTeamId: string } {
  if (hasLockedSpread(game)) {
    return {
      spread: Math.abs(game.lockedSpread as number),
      spreadTeamId: game.lockedSpreadTeamId as string,
    };
  }
  const spread =
    typeof game.spread === "number" && Number.isFinite(game.spread) ? Math.abs(game.spread) : 0;
  const spreadTeamId =
    typeof game.spreadTeamId === "string" && game.spreadTeamId.length > 0 ? game.spreadTeamId : "";
  return { spread, spreadTeamId };
}

export type LockedSpreadPatch =
  | { op: "set"; lockedSpread: number; lockedSpreadTeamId: string }
  | { op: "clear" };

/** Capture the league line at lock. Clear it when this game is open again. */
export function lockedSpreadPatch(
  game: {
    spread?: unknown;
    spreadTeamId?: unknown;
    lockedSpread?: unknown;
    lockedSpreadTeamId?: unknown;
  },
  locked: boolean
): LockedSpreadPatch | null {
  if (locked) {
    if (hasLockedSpread(game)) return null;
    const spread =
      typeof game.spread === "number" && Number.isFinite(game.spread) ? Math.abs(game.spread) : null;
    const spreadTeamId = typeof game.spreadTeamId === "string" ? game.spreadTeamId : "";
    if (spread == null || spreadTeamId === "") return null;
    return { op: "set", lockedSpread: spread, lockedSpreadTeamId: spreadTeamId };
  }
  if (game.lockedSpread == null && (game.lockedSpreadTeamId == null || game.lockedSpreadTeamId === "")) {
    return null;
  }
  return { op: "clear" };
}

export type LeagueSpreadWrite =
  | { allowed: true; patch: { spread: number; spreadTeamId: string } }
  | { allowed: false; reason: "locked" | "invalid" };

/** Commissioner or job write of the league line. Rejected once the game is locked. */
export function planLeagueSpreadWrite(input: {
  week: WeekLockInput;
  game: GameLockInput;
  now: number;
  spread: unknown;
  spreadTeamId: unknown;
}): LeagueSpreadWrite {
  if (gameEffectivelyLocked(input.week, input.game, input.now)) {
    return { allowed: false, reason: "locked" };
  }
  if (typeof input.spread !== "number" || !Number.isFinite(input.spread)) {
    return { allowed: false, reason: "invalid" };
  }
  if (typeof input.spreadTeamId !== "string" || input.spreadTeamId.trim() === "") {
    return { allowed: false, reason: "invalid" };
  }
  return {
    allowed: true,
    patch: { spread: Math.abs(input.spread), spreadTeamId: input.spreadTeamId },
  };
}

export interface LiveLine {
  liveSpread: number;
  liveSpreadTeamId: string;
}

/**
 * Odds/ESPN refresh. Always the reference line, never `spread` or `lockedSpread`.
 * Returns null when the stored live line already matches.
 */
export function oddsRefreshPatch(
  game: { liveSpread?: unknown; liveSpreadTeamId?: unknown },
  incoming: LiveLine | null
): LiveLine | null {
  if (!incoming) return null;
  if (!Number.isFinite(incoming.liveSpread) || incoming.liveSpreadTeamId.trim() === "") return null;
  const liveSpread = Math.abs(incoming.liveSpread);
  if (game.liveSpread === liveSpread && game.liveSpreadTeamId === incoming.liveSpreadTeamId) {
    return null;
  }
  return { liveSpread, liveSpreadTeamId: incoming.liveSpreadTeamId };
}

/** Parenthetical movement. Same normalization as iOS `SpreadLineCopy`. */
export function movementCaption(lockedLabel: string, liveLabel: string | null | undefined): string {
  if (!liveLabel) return lockedLabel;
  const live = liveLabel.trim();
  if (!live || normalizeLine(live) === normalizeLine(lockedLabel)) return lockedLabel;
  return `${lockedLabel} (${live})`;
}

function normalizeLine(value: string): string {
  let collapsed = value.replace(/ /g, "").toLowerCase();
  if (collapsed.endsWith(".0")) collapsed = collapsed.slice(0, -2);
  return collapsed;
}

export function spreadDisplayLabel(input: {
  spread: number;
  spreadTeamId: string;
  homeTeamId: string;
  awayTeamId: string;
  homeAbbr: string;
  awayAbbr: string;
}): string {
  const abbr =
    input.spreadTeamId === input.homeTeamId
      ? input.homeAbbr
      : input.spreadTeamId === input.awayTeamId
        ? input.awayAbbr
        : input.homeAbbr;
  return `${abbr} -${Math.abs(input.spread).toFixed(1)}`;
}

/**
 * Pick ids whose team changed on a game that is still locked.
 * Omitted keys are not treated as clears: admin merges the picks map.
 */
export function rejectedPickIds(input: {
  week: WeekLockInput;
  games: Array<GameLockInput & { id: string }>;
  before: Record<string, string>;
  after: Record<string, string>;
  now: number;
  beforeConfidence?: unknown;
  afterConfidence?: unknown;
}): string[] {
  const byId = new Map(input.games.map((game) => [game.id, game]));
  const blocked: string[] = [];
  for (const [gameId, teamId] of Object.entries(input.after)) {
    if ((input.before[gameId] ?? "") === teamId) continue;
    const game = byId.get(gameId) ?? { id: gameId };
    if (gameEffectivelyLocked(input.week, game, input.now)) blocked.push(gameId);
  }
  const beforeC = typeof input.beforeConfidence === "string" ? input.beforeConfidence : "";
  const afterC = typeof input.afterConfidence === "string" ? input.afterConfidence : "";
  if (afterC !== beforeC && afterC !== "") {
    const game = byId.get(afterC) ?? { id: afterC };
    if (gameEffectivelyLocked(input.week, game, input.now)) blocked.push(afterC);
  }
  return blocked;
}
