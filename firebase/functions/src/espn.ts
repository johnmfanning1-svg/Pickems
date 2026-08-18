import fetch from "node-fetch";

export interface EspnCompetitor {
  id: string;
  homeAway: string;
  score?: string;
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
