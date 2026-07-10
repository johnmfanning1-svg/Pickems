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
  competitions?: Array<{
    competitors?: EspnCompetitor[];
    status?: { type?: { completed?: boolean; state?: string } };
  }>;
}

export async function fetchScoreboard(week?: number): Promise<EspnEvent[]> {
  const base =
    "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard";
  const url = week ? `${base}?week=${week}&groups=80` : `${base}?groups=80`;
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`ESPN scoreboard failed: ${res.status}`);
  }
  const json = (await res.json()) as { events?: EspnEvent[] };
  return json.events ?? [];
}

export function parseEventScores(event: EspnEvent): {
  homeScore: number;
  awayScore: number;
  homeTeamId: string;
  awayTeamId: string;
  completed: boolean;
  inProgress: boolean;
} | null {
  const competition = event.competitions?.[0];
  if (!competition?.competitors || competition.competitors.length < 2) {
    return null;
  }
  const home = competition.competitors.find((c) => c.homeAway === "home");
  const away = competition.competitors.find((c) => c.homeAway === "away");
  if (!home || !away) return null;
  const state = competition.status?.type?.state ?? "";
  return {
    homeScore: Number(home.score ?? 0),
    awayScore: Number(away.score ?? 0),
    homeTeamId: home.team.id,
    awayTeamId: away.team.id,
    completed: competition.status?.type?.completed === true || state === "post",
    inProgress: state === "in",
  };
}
