import { stableHash, MAX_PUSH_BODY_LENGTH, MAX_PUSH_TITLE_LENGTH } from "./pushCopy";
import { pickedTeamId } from "./scoring";

/**
 * Cheeky push for a locked slate game that went final with no pick.
 * A miss is an automatic loss. Several games finalizing in one run collapse
 * into a single push. `notifyGameFinals` (the game_final pref) gates delivery;
 * this planner only sees the boolean the caller already resolved.
 */

export const NO_PICK_TITLE = "No pick";

export const NO_PICK_SINGLE_TEMPLATES = [
  "You didn't pick {away} @ {home}. That's a loss. Bold strategy.",
  "No pick, no points. {score}.",
  "Forgot to pick? The loss column didn't.",
  "{away} @ {home} is final. You weren't even in the building.",
  "Zero effort, one loss. Set an alarm next week.",
  "Missed the pick. The group chat noticed.",
] as const;

export const NO_PICK_MULTI_TEMPLATES = [
  "No pick on {n} games. That's {n} losses. Impressive commitment to nothing.",
  "{n} games, zero picks. The loss column says thanks.",
] as const;

const PLAIN_SINGLE = "{away} @ {home} is final. No pick counts as a loss.";
const PLAIN_MULTI = "No pick on {n} games. That's {n} losses.";

const TOKEN = /\{(\w+)\}/g;

export interface NoPickGame {
  id: string;
  locked: boolean;
  away: string;
  home: string;
  /** `AWAY n, HOME n`, or null when the final score is missing. */
  score: string | null;
}

export interface NoPickPlan {
  userId: string;
  gameIds: string[];
  title: string;
  body: string;
}

export interface NoPickPlanInput {
  weekStatus: unknown;
  games: readonly NoPickGame[];
  userId: string;
  picks?: Record<string, string> | null;
  /** False skips. Anything else sends, matching the pref default of on. */
  wantsGameFinals: boolean;
  /** False sends the plain sentence. Anything else is spicy. */
  spicyAlerts: boolean;
  alreadyNotifiedGameIds?: readonly string[];
}

export function planNoPickPush(input: NoPickPlanInput): NoPickPlan | null {
  try {
    return plan(input);
  } catch {
    return null;
  }
}

/** Game ids already claimed on `groups/{gid}/weeks/{wid}/noPickAlerts/{userId}`. */
export function notifiedNoPickGameIds(data: unknown): string[] {
  if (!data || typeof data !== "object") return [];
  const ids = (data as { gameIds?: unknown }).gameIds;
  if (!Array.isArray(ids)) return [];
  return ids.filter((id): id is string => typeof id === "string" && id.trim().length > 0);
}

export function noPickGameFromSlate(game: {
  id: string;
  locked: boolean;
  awayTeamAbbreviation?: unknown;
  homeTeamAbbreviation?: unknown;
  awayTeamName?: unknown;
  homeTeamName?: unknown;
  awayScore?: unknown;
  homeScore?: unknown;
}): NoPickGame {
  const away = teamTag(game.awayTeamAbbreviation, game.awayTeamName, "AWAY");
  const home = teamTag(game.homeTeamAbbreviation, game.homeTeamName, "HOME");
  return {
    id: game.id,
    locked: game.locked,
    away,
    home,
    score: scoreLabel(away, home, game.awayScore, game.homeScore),
  };
}

function plan(input: NoPickPlanInput): NoPickPlan | null {
  const status = typeof input.weekStatus === "string" ? input.weekStatus : "";
  if (status !== "picking" && status !== "locked") return null;
  if (input.wantsGameFinals === false) return null;

  const userId = input.userId.trim();
  if (!userId) return null;

  const already = new Set(input.alreadyNotifiedGameIds ?? []);
  const picks = input.picks ?? {};
  const missed: NoPickGame[] = [];
  const seen = new Set<string>();
  for (const game of input.games) {
    if (!game.locked) continue;
    const id = game.id.trim();
    if (!id || seen.has(id) || already.has(id)) continue;
    if (pickedTeamId(picks, id)) continue;
    seen.add(id);
    missed.push(game);
  }
  missed.sort((left, right) => (left.id < right.id ? -1 : left.id > right.id ? 1 : 0));
  if (missed.length === 0) return null;

  const spicy = input.spicyAlerts !== false;
  const body = missed.length === 1 ? singleBody(missed[0], userId, spicy) : multiBody(missed, userId, spicy);
  return {
    userId,
    gameIds: missed.map((game) => game.id),
    title: clip(NO_PICK_TITLE, MAX_PUSH_TITLE_LENGTH),
    body: clip(body, MAX_PUSH_BODY_LENGTH),
  };
}

function singleBody(game: NoPickGame, userId: string, spicy: boolean): string {
  const away = game.away.trim() || "AWAY";
  const home = game.home.trim() || "HOME";
  if (!spicy) return fill(PLAIN_SINGLE, { away, home, score: game.score, n: "1" }) ?? PLAIN_SINGLE;
  const lines = NO_PICK_SINGLE_TEMPLATES.map((template) =>
    fill(template, { away, home, score: game.score, n: "1" })
  ).filter((line): line is string => line != null);
  if (lines.length === 0) {
    return fill(PLAIN_SINGLE, { away, home, score: game.score, n: "1" }) ?? "No pick counts as a loss.";
  }
  return lines[stableHash(`${userId}:${game.id}`) % lines.length];
}

function multiBody(games: readonly NoPickGame[], userId: string, spicy: boolean): string {
  const n = String(games.length);
  const tokens = { away: null, home: null, score: null, n };
  if (!spicy) return fill(PLAIN_MULTI, tokens) ?? `No pick on ${n} games. That's ${n} losses.`;
  const lines = NO_PICK_MULTI_TEMPLATES.map((template) => fill(template, tokens)).filter(
    (line): line is string => line != null
  );
  if (lines.length === 0) return fill(PLAIN_MULTI, tokens) ?? `No pick on ${n} games. That's ${n} losses.`;
  const key = `${userId}:${games.map((game) => game.id).join(",")}`;
  return lines[stableHash(key) % lines.length];
}

function fill(template: string, tokens: Record<string, string | null>): string | null {
  let missing = false;
  const filled = template.replace(TOKEN, (whole, key: string) => {
    const value = tokens[key];
    if (value == null || value === "") {
      missing = true;
      return whole;
    }
    return value;
  });
  if (missing) return null;
  const clean = filled.replace(/\s+/g, " ").trim();
  return clean.length > 0 ? clean : null;
}

function teamTag(abbreviation: unknown, name: unknown, fallback: string): string {
  if (typeof abbreviation === "string" && abbreviation.trim()) return abbreviation.trim();
  if (typeof name === "string" && name.trim()) return name.trim().slice(0, 4).toUpperCase();
  return fallback;
}

function scoreLabel(away: string, home: string, awayScore: unknown, homeScore: unknown): string | null {
  const awayPoints = finiteScore(awayScore);
  const homePoints = finiteScore(homeScore);
  if (awayPoints == null || homePoints == null) return null;
  return `${away} ${formatScore(awayPoints)}, ${home} ${formatScore(homePoints)}`;
}

function finiteScore(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function formatScore(value: number): string {
  if (Math.abs(value - Math.round(value)) < 1e-6) return String(Math.round(value));
  return String(value);
}

function clip(value: string, max: number): string {
  const clean = value.replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  if (max === MAX_PUSH_BODY_LENGTH) {
    const cut = clean.slice(0, max - 1);
    const word = cut.lastIndexOf(" ");
    const base = word > 40 ? cut.slice(0, word) : cut;
    return `${base.trimEnd()}…`;
  }
  return clean.slice(0, max).trimEnd();
}
