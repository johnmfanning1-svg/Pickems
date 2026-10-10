import fetch from "node-fetch";

export interface EspnCompetitor {
  id: string;
  homeAway: string;
  score?: string;
  /** Points per period when the scoreboard includes them. Not always present. */
  linescores?: unknown;
  team: {
    id: string;
    displayName: string;
    abbreviation: string;
    logo?: string;
  };
}

export interface EspnEvent {
  id: string;
  date?: string;
  competitions?: Array<{
    competitors?: EspnCompetitor[];
    status?: { type?: { completed?: boolean; state?: string } };
    odds?: Array<{
      spread?: number;
      details?: string;
      homeTeamOdds?: { favorite?: boolean };
      awayTeamOdds?: { favorite?: boolean };
    }>;
    broadcasts?: Array<{ market?: string; names?: string[] }>;
    geoBroadcasts?: Array<{ media?: { shortName?: string; name?: string } }>;
    neutralSite?: boolean;
  }>;
}

export interface ParsedEventScores {
  homeScore: number | null;
  awayScore: number | null;
  homeTeamId: string;
  awayTeamId: string;
  completed: boolean;
  inProgress: boolean;
  /** Per-period points. Null when ESPN omitted linescores or any entry was unusable. */
  homeLineScores?: number[] | null;
  awayLineScores?: number[] | null;
}

const SCOREBOARD_BASE =
  "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard";

export function scoreboardURL(options?: { week?: number; seasonType?: number }): string {
  const params = new URLSearchParams({ groups: "80", limit: "300" });
  if (options?.week != null) params.set("week", String(options.week));
  if (options?.seasonType != null) params.set("seasontype", String(options.seasonType));
  return `${SCOREBOARD_BASE}?${params.toString()}`;
}

export function parseCompetitorScore(raw: string | undefined): number | null {
  if (raw == null || raw.trim() === "") return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

/**
 * ESPN linescores are points scored in each period (not a running total).
 * One bad entry drops the list so halftime math cannot run on a hole.
 */
export function parseLineScoreList(raw: unknown): number[] | null {
  if (!Array.isArray(raw) || raw.length === 0) return null;
  const scores: number[] = [];
  for (const item of raw) {
    const value = lineScoreValue(item);
    if (value == null || value < 0) return null;
    scores.push(value);
  }
  return scores;
}

function lineScoreValue(item: unknown): number | null {
  if (typeof item === "number" && Number.isFinite(item)) return item;
  if (typeof item === "string" && item.trim() !== "") {
    const parsed = Number(item);
    return Number.isFinite(parsed) ? parsed : null;
  }
  if (!item || typeof item !== "object") return null;
  const record = item as { value?: unknown; displayValue?: unknown };
  if (typeof record.value === "number" && Number.isFinite(record.value)) return record.value;
  if (typeof record.displayValue === "string" && record.displayValue.trim() !== "") {
    const parsed = Number(record.displayValue);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export async function fetchScoreboard(options?: {
  week?: number;
  seasonType?: number;
  timeoutMs?: number;
}): Promise<EspnEvent[]> {
  const url = scoreboardURL(options);
  const timeoutMs = options?.timeoutMs ?? 10_000;
  const res = await fetch(url, { timeout: timeoutMs });
  if (!res.ok) {
    throw new Error(`ESPN scoreboard failed: ${res.status}`);
  }
  const json = (await res.json()) as { events?: EspnEvent[] };
  return json.events ?? [];
}

/**
 * Favorite for a stored slate: flags first, then ESPN's home-centric spread
 * (negative = home favored, positive = away favored). Never default to away
 * just because `homeTeamOdds.favorite` is missing.
 */
export function resolveSpreadTeamId(options: {
  homeTeamId: string;
  awayTeamId: string;
  spread?: number;
  homeFavorite?: boolean;
  awayFavorite?: boolean;
}): string {
  if (options.homeFavorite === true) return options.homeTeamId;
  if (options.awayFavorite === true) return options.awayTeamId;
  if (typeof options.spread === "number" && options.spread > 0) return options.awayTeamId;
  return options.homeTeamId;
}

export function parseEventScores(event: EspnEvent): ParsedEventScores | null {
  const competition = event.competitions?.[0];
  if (!competition?.competitors || competition.competitors.length < 2) {
    return null;
  }
  const home = competition.competitors.find((c) => c.homeAway === "home");
  const away = competition.competitors.find((c) => c.homeAway === "away");
  if (!home || !away) return null;
  const state = competition.status?.type?.state ?? "";
  return {
    homeScore: parseCompetitorScore(home.score),
    awayScore: parseCompetitorScore(away.score),
    homeTeamId: home.team.id,
    awayTeamId: away.team.id,
    completed: competition.status?.type?.completed === true || state === "post",
    inProgress: state === "in",
    homeLineScores: parseLineScoreList(home.linescores),
    awayLineScores: parseLineScoreList(away.linescores),
  };
}

/** Final only when ESPN says complete *and* both scores are present — never invent 0–0. */
export function nextGameStatus(
  current: "scheduled" | "inProgress" | "final",
  parsed: ParsedEventScores | null
): "scheduled" | "inProgress" | "final" {
  if (!parsed) return current;
  const hasScores = parsed.homeScore != null && parsed.awayScore != null;
  if (parsed.completed && hasScores) return "final";
  if (parsed.inProgress) return "inProgress";
  return current;
}

export function slateGameNeedsWrite(
  game: {
    status: string;
    homeScore?: number | null;
    awayScore?: number | null;
  },
  nextStatus: string,
  parsed: ParsedEventScores
): boolean {
  if (game.status !== nextStatus) return true;
  if (parsed.homeScore != null && game.homeScore !== parsed.homeScore) return true;
  if (parsed.awayScore != null && game.awayScore !== parsed.awayScore) return true;
  return false;
}
