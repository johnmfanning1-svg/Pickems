import type { Message, Aps } from "firebase-admin/messaging";
import { teamTag } from "./pushAlert";
import { kickoffMillis } from "./pickLock";
import {
  applyLatePickPenalty,
  coveredTeamId,
  pickedTeamId,
  rankEntries,
  scorePicks,
  type PickMode,
  type SlateGameDoc,
} from "./scoring";

/**
 * Lock-screen Live Activity payload. Keep in sync with
 * `Pickems/Features/Live/LiveActivityContent.swift`.
 *
 * Pushes go through FCM (`apns.liveActivityToken` on firebase-admin 14), which
 * already authenticates this project. The ActivityKit token is not an FCM
 * registration token; FCM still requires the device token beside it. Raw APNs
 * would need a .p8 the functions do not have.
 */
export const LIVE_ACTIVITY_CONTENT_VERSION = 2;
export const MAX_LIVE_ACTIVITY_PICKS = 3;
export const LIVE_ACTIVITY_STALE_SECONDS = 20 * 60;
export const LIVE_ACTIVITY_DISMISS_SECONDS = 3 * 60 * 60;

export const LIVE_ACTIVITY_FIELDS = {
  token: "liveActivityToken",
  groupId: "liveActivityGroupId",
  weekId: "liveActivityWeekId",
  key: "liveActivityKey",
} as const;

export function liveActivityKey(groupId: string, weekId: string): string {
  return `${groupId}|${weekId}`;
}

export interface LiveActivityPickPayload {
  gameId: string;
  picked: string;
  opponent: string;
  pickedScore?: number;
  opponentScore?: number;
  phase: "live" | "upcoming" | "final";
  result: "pending" | "covering" | "trailing" | "won" | "lost" | "push";
  resultLabel: string;
  kickoffUnix: number;
}

export interface LiveActivityContentState {
  weeklyWins: number;
  weeklyLosses: number;
  weeklyPushes: number;
  rank?: number;
  rankTied: boolean;
  picks: LiveActivityPickPayload[];
  updatedAt: number;
  contentVersion: number;
}

export interface LiveActivityRecord {
  wins: number;
  losses: number;
  pushes: number;
  rank: number | null;
  rankTied: boolean;
}

export interface LiveActivityPickSource {
  picks: Record<string, string>;
  confidenceGameId?: string | null;
  submittedAt?: unknown;
}

export interface LiveActivitySubscription {
  userId: string;
  fcmToken: string;
  liveActivityToken: string;
}

export interface PlannedLiveActivityPush {
  userId: string;
  event: "update" | "end";
  pickCount: number;
  message: Message;
}

interface Candidate {
  game: SlateGameDoc;
  pickedTeamId: string;
  kickoffMs: number;
}

export function scoreLiveActivityBoard(input: {
  members: Array<{ id: string; displayName: string }>;
  picksByUserId: Record<string, LiveActivityPickSource>;
  games: SlateGameDoc[];
  pickMode: PickMode;
  applyLatePenalty?: boolean;
  latePickPenaltyWins?: number;
  deadline?: unknown;
}): Map<string, LiveActivityRecord> {
  const scored = input.members.map((member) => {
    const source = input.picksByUserId[member.id];
    const result = applyLatePickPenalty(
      scorePicks(source?.picks ?? {}, input.games, source?.confidenceGameId, {
        pickMode: input.pickMode,
      }),
      {
        allowLatePicks: input.applyLatePenalty === true,
        latePickPenaltyWins: input.latePickPenaltyWins ?? 0,
        submittedAt: source?.submittedAt,
        deadline: input.deadline,
      }
    );
    return {
      id: member.id,
      displayName: member.displayName,
      avatarColorHex: "",
      weeklyWins: result.wins,
      weeklyLosses: result.losses,
      seasonWins: 0,
      seasonLosses: 0,
      pushes: result.pushes,
    };
  });
  const ranked = rankEntries(scored);
  const pushesById = new Map(scored.map((entry) => [entry.id, entry.pushes]));
  const records = new Map<string, LiveActivityRecord>();
  for (const entry of ranked) {
    const decided = entry.weeklyWins + entry.weeklyLosses > 0;
    const shared =
      decided && ranked.filter((other) => other.rank === entry.rank).length > 1;
    records.set(entry.id, {
      wins: entry.weeklyWins,
      losses: entry.weeklyLosses,
      pushes: pushesById.get(entry.id) ?? 0,
      rank: decided ? entry.rank : null,
      rankTied: shared,
    });
  }
  return records;
}

export function buildLiveActivityContentState(input: {
  games: SlateGameDoc[];
  picks: Record<string, string>;
  pickMode: PickMode;
  wins: number;
  losses: number;
  pushes: number;
  rank: number | null;
  rankTied: boolean;
  updatedAt: number;
}): LiveActivityContentState {
  const showRank = input.wins + input.losses > 0 && input.rank != null && input.rank > 0;
  const state: LiveActivityContentState = {
    weeklyWins: input.wins,
    weeklyLosses: input.losses,
    weeklyPushes: input.pushes,
    rankTied: showRank && input.rankTied,
    picks: selectPicks(input.games, input.picks, input.pickMode),
    updatedAt: input.updatedAt,
    contentVersion: LIVE_ACTIVITY_CONTENT_VERSION,
  };
  if (showRank && input.rank != null) state.rank = input.rank;
  return state;
}

export function planLiveActivityPushes(input: {
  games: SlateGameDoc[];
  members: Array<{ id: string; displayName: string }>;
  picksByUserId: Record<string, LiveActivityPickSource>;
  subscriptions: LiveActivitySubscription[];
  changedGameIds: ReadonlySet<string>;
  pickMode: PickMode;
  applyLatePenalty?: boolean;
  latePickPenaltyWins?: number;
  deadline?: unknown;
  dismiss: boolean;
  nowMs: number;
}): PlannedLiveActivityPush[] {
  const records = scoreLiveActivityBoard(input);
  const nowSec = Math.floor(input.nowMs / 1000);
  const plans: PlannedLiveActivityPush[] = [];
  for (const subscription of input.subscriptions) {
    const fcmToken = subscription.fcmToken.trim();
    const liveActivityToken = subscription.liveActivityToken.trim();
    if (!fcmToken || !liveActivityToken) continue;
    const record = records.get(subscription.userId);
    if (!record) continue;
    const source = input.picksByUserId[subscription.userId];
    const picks = source?.picks ?? {};
    if (!input.dismiss && !pickedChangedGame(picks, input.changedGameIds)) continue;
    const contentState = buildLiveActivityContentState({
      games: input.games,
      picks,
      pickMode: input.pickMode,
      wins: record.wins,
      losses: record.losses,
      pushes: record.pushes,
      rank: record.rank,
      rankTied: record.rankTied,
      updatedAt: nowSec,
    });
    const event = input.dismiss ? "end" : "update";
    plans.push({
      userId: subscription.userId,
      event,
      pickCount: contentState.picks.length,
      message: liveActivityMessage({
        fcmToken,
        liveActivityToken,
        event,
        contentState,
        nowSec,
      }),
    });
  }
  return plans;
}

export function liveActivityMessage(input: {
  fcmToken: string;
  liveActivityToken: string;
  event: "update" | "end";
  contentState: LiveActivityContentState;
  nowSec: number;
}): Message {
  const aps: Aps = {
    timestamp: input.nowSec,
    event: input.event,
  };
  aps["content-state"] = input.contentState;
  if (input.event === "end") {
    aps["dismissal-date"] = input.nowSec + LIVE_ACTIVITY_DISMISS_SECONDS;
  } else {
    aps["stale-date"] = input.nowSec + LIVE_ACTIVITY_STALE_SECONDS;
  }
  return {
    token: input.fcmToken,
    apns: {
      liveActivityToken: input.liveActivityToken,
      headers: {
        "apns-priority": "10",
        "apns-push-type": "liveactivity",
      },
      payload: { aps },
    },
  };
}

/** APNs rejected the activity token. An unregistered FCM device token is a different field. */
export function isStaleLiveActivityTokenError(err: unknown): boolean {
  const code = errorCode(err);
  if (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token"
  ) {
    return false;
  }
  return /BadDeviceToken|DeviceTokenNotForTopic|Unregistered|ExpiredToken/i.test(errorText(err));
}

export function pickedChangedGame(
  picks: Record<string, string> | undefined,
  changedGameIds: ReadonlySet<string>
): boolean {
  if (!picks || changedGameIds.size === 0) return false;
  for (const gameId of changedGameIds) {
    if (pickedTeamId(picks, gameId)) return true;
  }
  return false;
}

function selectPicks(
  games: SlateGameDoc[],
  picks: Record<string, string>,
  pickMode: PickMode
): LiveActivityPickPayload[] {
  const mine: Candidate[] = [];
  for (const game of games) {
    const picked = pickedTeamId(picks, game.id);
    if (!picked) continue;
    if (picked !== game.homeTeamId && picked !== game.awayTeamId) continue;
    mine.push({ game, pickedTeamId: picked, kickoffMs: kickoffMillis(game.kickoff) ?? 0 });
  }
  const live = mine.filter((item) => item.game.status === "inProgress").sort(earlierKickoff);
  const upcoming = mine.filter((item) => item.game.status === "scheduled").sort(earlierKickoff);
  const finals = mine.filter((item) => item.game.status === "final").sort(laterKickoff);
  const chosen: Candidate[] = [];
  for (const item of live) {
    if (chosen.length >= MAX_LIVE_ACTIVITY_PICKS) break;
    chosen.push(item);
  }
  if (chosen.length < MAX_LIVE_ACTIVITY_PICKS && upcoming.length > 0) {
    chosen.push(upcoming[0]);
  }
  for (const item of finals) {
    if (chosen.length >= MAX_LIVE_ACTIVITY_PICKS) break;
    chosen.push(item);
  }
  return chosen.map((item) => pickRow(item, pickMode));
}

function earlierKickoff(lhs: Candidate, rhs: Candidate): number {
  if (lhs.kickoffMs !== rhs.kickoffMs) return lhs.kickoffMs - rhs.kickoffMs;
  return lhs.game.id < rhs.game.id ? -1 : lhs.game.id > rhs.game.id ? 1 : 0;
}

function laterKickoff(lhs: Candidate, rhs: Candidate): number {
  if (lhs.kickoffMs !== rhs.kickoffMs) return rhs.kickoffMs - lhs.kickoffMs;
  return lhs.game.id < rhs.game.id ? -1 : lhs.game.id > rhs.game.id ? 1 : 0;
}

function pickRow(candidate: Candidate, pickMode: PickMode): LiveActivityPickPayload {
  const game = candidate.game;
  const pickedIsHome = candidate.pickedTeamId === game.homeTeamId;
  const graded = grade(game, candidate.pickedTeamId, pickMode);
  const ready = game.status !== "scheduled" && game.homeScore != null && game.awayScore != null;
  const row: LiveActivityPickPayload = {
    gameId: game.id,
    picked: teamTag(
      pickedIsHome ? game.homeTeamAbbreviation : game.awayTeamAbbreviation,
      pickedIsHome ? game.homeTeamName : game.awayTeamName,
      "TEAM"
    ),
    opponent: teamTag(
      pickedIsHome ? game.awayTeamAbbreviation : game.homeTeamAbbreviation,
      pickedIsHome ? game.awayTeamName : game.homeTeamName,
      "TEAM"
    ),
    phase: phase(game.status),
    result: graded.result,
    resultLabel: graded.resultLabel,
    kickoffUnix: (kickoffMillis(game.kickoff) ?? 0) / 1000,
  };
  if (ready) {
    const pickedScore = pickedIsHome ? game.homeScore : game.awayScore;
    const opponentScore = pickedIsHome ? game.awayScore : game.homeScore;
    if (pickedScore != null) row.pickedScore = pickedScore;
    if (opponentScore != null) row.opponentScore = opponentScore;
  }
  return row;
}

function grade(
  game: SlateGameDoc,
  picked: string,
  pickMode: PickMode
): { result: LiveActivityPickPayload["result"]; resultLabel: string } {
  if (game.status === "inProgress" && (game.homeScore == null || game.awayScore == null)) {
    return { result: "pending", resultLabel: "Live" };
  }
  if (
    game.status === "inProgress" &&
    game.homeScore != null &&
    game.awayScore != null &&
    coveredTeamId(game, game.homeScore, game.awayScore, pickMode) == null
  ) {
    return pickMode === "straightUp"
      ? { result: "push", resultLabel: "Tied" }
      : { result: "push", resultLabel: "Pushing" };
  }
  if (game.homeScore == null || game.awayScore == null || game.status === "scheduled") {
    return { result: "pending", resultLabel: "Pending" };
  }
  const covered = coveredTeamId(game, game.homeScore, game.awayScore, pickMode);
  if (covered == null) return { result: "push", resultLabel: "Push" };
  const hit = covered === picked;
  if (game.status === "final") {
    return hit ? { result: "won", resultLabel: "Won" } : { result: "lost", resultLabel: "Lost" };
  }
  if (game.status === "inProgress") {
    if (pickMode === "straightUp") {
      return hit
        ? { result: "covering", resultLabel: "Winning" }
        : { result: "trailing", resultLabel: "Losing" };
    }
    return hit
      ? { result: "covering", resultLabel: "Covering" }
      : { result: "trailing", resultLabel: "Trailing" };
  }
  return { result: "pending", resultLabel: "Pending" };
}

function phase(status: SlateGameDoc["status"]): LiveActivityPickPayload["phase"] {
  if (status === "inProgress") return "live";
  if (status === "final") return "final";
  return "upcoming";
}

function errorCode(err: unknown): string {
  if (!err || typeof err !== "object") return "";
  const record = err as { code?: unknown; errorInfo?: { code?: unknown } };
  if (typeof record.code === "string") return record.code;
  if (typeof record.errorInfo?.code === "string") return record.errorInfo.code;
  return "";
}

function errorText(err: unknown): string {
  if (typeof err === "string") return err;
  if (err instanceof Error) return err.message;
  if (!err || typeof err !== "object") return "";
  const record = err as { message?: unknown; errorInfo?: { message?: unknown } };
  const parts = [record.message, record.errorInfo?.message].filter(
    (part): part is string => typeof part === "string"
  );
  return parts.join(" ");
}
