import type { Message, Aps } from "firebase-admin/messaging";
import type { PickMode } from "./scoring";

/** Lock-screen context line. APNs draws this under the title. */
export const MAX_PUSH_SUBTITLE_LENGTH = 50;

export type PushPayloadType = "game_final" | "no_pick" | "lead" | "selection_veto";

export interface PushPresentation {
  subtitle?: string;
  /** Data `type` when it differs from the preference type (`took_the_lead` → `lead`). */
  payloadType?: string;
  /** APNs `thread-id`. One per league so Notification Center groups that league's alerts. */
  threadId?: string;
  /**
   * APNs `apns-collapse-id`. Per alert, not per league: a retry replaces that
   * game's banner, and a second game stays on screen inside the league thread.
   */
  collapseId?: string;
}

export interface BuiltPush {
  subtitle: string;
  threadId: string;
  collapseId: string;
  payloadType: PushPayloadType;
  /** `type`, `groupId`, `weekId`, `deepLink`, and `gameId` when the tap targets one game. */
  data: Record<string, string>;
}

export interface MatchupInput {
  away: string;
  home: string;
  awayScore?: number | null;
  homeScore?: number | null;
  /** ATS favorite tag such as `OSU -7`. Omitted for Straight Up and when it will not fit. */
  spreadLabel?: string | null;
}

const SEPARATOR = " · ";

export function leagueDisplayName(value: unknown): string {
  if (typeof value !== "string") return "League";
  const trimmed = value.replace(/\s+/g, " ").trim();
  return trimmed.length > 0 ? trimmed : "League";
}

export function leagueThreadId(groupId: string): string {
  return `league-${groupId}`;
}

/** One collapse id per alert. Capped at APNs' 64-byte header limit. */
export function alertCollapseId(groupId: string, kind: string, id: string): string {
  const raw = `${leagueThreadId(groupId)}:${kind}:${id}`;
  return raw.length <= 64 ? raw : raw.slice(0, 64);
}

export function gameDeepLink(groupId: string, weekId: string, gameId: string): string {
  return `pickems://league/${encodeURIComponent(groupId)}/week/${encodeURIComponent(weekId)}/game/${encodeURIComponent(gameId)}`;
}

export function pickemsDeepLink(groupId: string, weekId: string): string {
  return `pickems://league/${encodeURIComponent(groupId)}/week/${encodeURIComponent(weekId)}/pickems`;
}

export function leaderboardDeepLink(groupId: string, weekId: string): string {
  return `pickems://league/${encodeURIComponent(groupId)}/week/${encodeURIComponent(weekId)}/leaderboard`;
}

export function teamTag(abbreviation: unknown, name: unknown, fallback: string): string {
  if (typeof abbreviation === "string" && abbreviation.trim()) {
    return abbreviation.trim().replace(/\s+/g, "").slice(0, 6);
  }
  if (typeof name === "string" && name.trim()) {
    return name.trim().slice(0, 4).toUpperCase();
  }
  return fallback;
}

export function spreadLabel(input: {
  spread?: unknown;
  spreadTeamId?: unknown;
  homeTeamId?: unknown;
  awayTeamId?: unknown;
  home: string;
  away: string;
}): string | null {
  const spread = finiteNumber(input.spread);
  if (spread == null || Math.abs(spread) < 1e-6) return null;
  const spreadTeamId = typeof input.spreadTeamId === "string" ? input.spreadTeamId : "";
  const homeTeamId = typeof input.homeTeamId === "string" ? input.homeTeamId : "";
  const awayTeamId = typeof input.awayTeamId === "string" ? input.awayTeamId : "";
  const favorite = spreadTeamId !== "" && spreadTeamId === homeTeamId
    ? input.home
    : spreadTeamId !== "" && spreadTeamId === awayTeamId
      ? input.away
      : "";
  if (!favorite) return null;
  return `${favorite} -${formatNumber(Math.abs(spread))}`;
}

/**
 * `{League} · {AWAY} {away} @ {HOME} {home}`, plus the ATS spread when the
 * whole line still fits in {@link MAX_PUSH_SUBTITLE_LENGTH}.
 */
export function gameContextSubtitle(leagueName: string, matchup: MatchupInput): string {
  const detail = matchupDetail(matchup);
  const base = composeSubtitle(leagueName, detail);
  const spread = clean(matchup.spreadLabel);
  if (!spread) return base;
  const withSpread = `${leagueDisplayName(leagueName)}${SEPARATOR}${detail}${SEPARATOR}${spread}`;
  // Keep the league name intact. The spread is extra, only when the full line fits.
  if (withSpread.length <= MAX_PUSH_SUBTITLE_LENGTH) return withSpread;
  return base;
}

export function multiGameSubtitle(leagueName: string, gameCount: number): string {
  const count = Number.isFinite(gameCount) && gameCount > 0 ? Math.floor(gameCount) : 1;
  return composeSubtitle(leagueName, `${count} games`);
}

export function leadContextSubtitle(leagueName: string, weekNumber: unknown): string {
  const week = finiteNumber(weekNumber);
  const label = week == null ? "This week" : `Week ${formatNumber(week)}`;
  return composeSubtitle(leagueName, label);
}

/** Android and other clients have no subtitle, so the matchup rides on the body. */
export function androidFallbackBody(body: string, subtitle?: string): string {
  const cleanBody = body.replace(/\s+/g, " ").trim();
  const cleanSubtitle = subtitle?.replace(/\s+/g, " ").trim();
  if (!cleanSubtitle) return cleanBody;
  return `${cleanBody} — ${cleanSubtitle}`;
}

export function buildGameFinalPush(input: {
  leagueName: unknown;
  groupId: string;
  weekId: string;
  gameId: string;
  pickMode?: PickMode | null;
  matchup: MatchupInput;
}): BuiltPush {
  const includeSpread = input.pickMode !== "straightUp";
  const subtitle = gameContextSubtitle(input.leagueName as string, {
    ...input.matchup,
    spreadLabel: includeSpread ? input.matchup.spreadLabel : null,
  });
  const threadId = leagueThreadId(input.groupId);
  return {
    subtitle,
    threadId,
    collapseId: alertCollapseId(input.groupId, "game", input.gameId),
    payloadType: "game_final",
    data: {
      type: "game_final",
      groupId: input.groupId,
      weekId: input.weekId,
      gameId: input.gameId,
      deepLink: gameDeepLink(input.groupId, input.weekId, input.gameId),
    },
  };
}

export function buildNoPickPush(input: {
  leagueName: unknown;
  groupId: string;
  weekId: string;
  pickMode?: PickMode | null;
  games: ReadonlyArray<MatchupInput & { id: string }>;
}): BuiltPush {
  const games = input.games.filter((game) => game.id.trim().length > 0);
  const threadId = leagueThreadId(input.groupId);
  if (games.length === 1) {
    const game = games[0];
    const gameId = game.id.trim();
    const subtitle = gameContextSubtitle(input.leagueName as string, {
      ...game,
      spreadLabel: input.pickMode === "straightUp" ? null : game.spreadLabel,
    });
    return {
      subtitle,
      threadId,
      collapseId: alertCollapseId(input.groupId, "nopick", gameId),
      payloadType: "no_pick",
      data: {
        type: "no_pick",
        groupId: input.groupId,
        weekId: input.weekId,
        gameId,
        deepLink: gameDeepLink(input.groupId, input.weekId, gameId),
      },
    };
  }
  const count = games.length;
  return {
    subtitle: multiGameSubtitle(input.leagueName as string, count),
    threadId,
    collapseId: alertCollapseId(input.groupId, "nopick", input.weekId),
    payloadType: "no_pick",
    data: {
      type: "no_pick",
      groupId: input.groupId,
      weekId: input.weekId,
      deepLink: pickemsDeepLink(input.groupId, input.weekId),
    },
  };
}

/** Selection veto. Names the league and the matchup, and opens that game. */
export function buildSelectionVetoPush(input: {
  leagueName: unknown;
  groupId: string;
  weekId: string;
  gameId: string;
  away: string;
  home: string;
}): BuiltPush {
  const subtitle = gameContextSubtitle(input.leagueName as string, {
    away: input.away,
    home: input.home,
  });
  const threadId = leagueThreadId(input.groupId);
  const gameId = input.gameId.trim();
  return {
    subtitle,
    threadId,
    collapseId: alertCollapseId(input.groupId, "veto", gameId),
    payloadType: "selection_veto",
    data: {
      type: "selection_veto",
      groupId: input.groupId,
      weekId: input.weekId,
      gameId,
      deepLink: gameDeepLink(input.groupId, input.weekId, gameId),
    },
  };
}

export function buildLeadPush(input: {
  leagueName: unknown;
  groupId: string;
  weekId: string;
  weekNumber: unknown;
}): BuiltPush {
  const threadId = leagueThreadId(input.groupId);
  return {
    subtitle: leadContextSubtitle(input.leagueName as string, input.weekNumber),
    threadId,
    collapseId: alertCollapseId(input.groupId, "lead", input.weekId),
    payloadType: "lead",
    data: {
      type: "lead",
      groupId: input.groupId,
      weekId: input.weekId,
      deepLink: leaderboardDeepLink(input.groupId, input.weekId),
    },
  };
}

/**
 * One FCM message for every push.
 * iOS reads `apns.payload.aps.alert` (title, subtitle, original body).
 * Android reads `android.notification.body`, which appends the subtitle.
 */
export function buildPushMessage(input: {
  token: string;
  title: string;
  body: string;
  data: Record<string, string>;
  presentation?: PushPresentation;
}): Message {
  const presentation = input.presentation;
  const subtitle = presentation?.subtitle?.trim();
  const aps: Aps = { sound: "default" };
  if (subtitle) {
    aps.alert = { title: input.title, subtitle, body: input.body };
  }
  if (presentation?.threadId) aps.threadId = presentation.threadId;

  const headers: Record<string, string> = {
    "apns-push-type": "alert",
    "apns-priority": "10",
  };
  if (presentation?.collapseId) headers["apns-collapse-id"] = presentation.collapseId;

  const message: Message = {
    token: input.token,
    notification: { title: input.title, body: input.body },
    data: input.data,
    apns: {
      headers,
      payload: { aps },
    },
  };

  if (subtitle || presentation?.threadId) {
    message.android = {
      priority: "high",
      collapseKey: presentation?.threadId,
      notification: {
        title: input.title,
        body: androidFallbackBody(input.body, subtitle),
      },
    };
  }
  return message;
}

export function matchupFromGame(game: {
  awayTeamAbbreviation?: unknown;
  awayTeamName?: unknown;
  homeTeamAbbreviation?: unknown;
  homeTeamName?: unknown;
  awayScore?: unknown;
  homeScore?: unknown;
  spread?: unknown;
  spreadTeamId?: unknown;
  homeTeamId?: unknown;
  awayTeamId?: unknown;
}): MatchupInput {
  const away = teamTag(game.awayTeamAbbreviation, game.awayTeamName, "AWAY");
  const home = teamTag(game.homeTeamAbbreviation, game.homeTeamName, "HOME");
  return {
    away,
    home,
    awayScore: finiteNumber(game.awayScore),
    homeScore: finiteNumber(game.homeScore),
    spreadLabel: spreadLabel({
      spread: game.spread,
      spreadTeamId: game.spreadTeamId,
      homeTeamId: game.homeTeamId,
      awayTeamId: game.awayTeamId,
      home,
      away,
    }),
  };
}

function matchupDetail(matchup: MatchupInput): string {
  const away = clean(matchup.away) || "AWAY";
  const home = clean(matchup.home) || "HOME";
  const awayScore = finiteNumber(matchup.awayScore);
  const homeScore = finiteNumber(matchup.homeScore);
  if (awayScore == null || homeScore == null) return `${away} @ ${home}`;
  return `${away} ${formatNumber(awayScore)} @ ${home} ${formatNumber(homeScore)}`;
}

function composeSubtitle(leagueName: string, detail: string): string {
  const league = leagueDisplayName(leagueName);
  const rest = clean(detail) || "Game";
  const room = MAX_PUSH_SUBTITLE_LENGTH - SEPARATOR.length - rest.length;
  if (room >= league.length) return clipSubtitle(`${league}${SEPARATOR}${rest}`);
  if (room >= 1) {
    const cut = league.slice(0, room).trimEnd();
    const name = cut.length > 0 ? cut : league.slice(0, room);
    return clipSubtitle(`${name}${SEPARATOR}${rest}`);
  }
  return clipSubtitle(rest);
}

function clipSubtitle(value: string): string {
  const cleanValue = value.replace(/\s+/g, " ").trim();
  if (cleanValue.length <= MAX_PUSH_SUBTITLE_LENGTH) return cleanValue;
  return cleanValue.slice(0, MAX_PUSH_SUBTITLE_LENGTH).trimEnd();
}

function clean(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.replace(/\s+/g, " ").trim();
}

function finiteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function formatNumber(value: number): string {
  if (Math.abs(value - Math.round(value)) < 1e-6) return String(Math.round(value));
  return (Math.round(value * 2) / 2).toFixed(1);
}
