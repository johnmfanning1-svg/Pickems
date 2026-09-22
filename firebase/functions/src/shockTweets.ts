import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { easternYmd } from "./cfbWeekCalendar";
import {
  coveredTeamId,
  pickedTeamId,
  resolveWeekPickMode,
  toMillis,
  type PickMode,
  type SlateGameDoc,
} from "./scoring";

/**
 * Shock Tweets v1 — anonymized pick-share drafts after surprising finals.
 * Posting to @CFB_PICKEMS is out of scope; this module only writes
 * `shockTweets/{id}` through the Admin SDK.
 *
 * Cloud Scheduler cron (America/New_York): every 20 minutes, hours 12–23,
 * Saturday and Sunday. `isShockTweetWindow` keeps the real work inside
 * Saturday 3:00pm–11:59pm ET and Sunday 12:00pm–12:59pm ET.
 */
export const SHOCK_TWEET_SCHEDULE = "*/20 12-23 * * 0,6";
export const SHOCK_TWEET_TIME_ZONE = "America/New_York";

export const SHOCK_TWEET_CONFIG = {
  /** Picks on that game, across leagues, in a single mode. */
  minPickCount: 10,
  /** Dog covers or wins outright when this share (or lower) took the dog. */
  dogPickPctMax: 35,
  /** Favorite fails to cover, or loses straight up, at this share or higher. */
  favoritePickPctMin: 70,
  /** Wait after the slate doc's last write so ESPN cannot flip the final. */
  settleDelayMs: 8 * 60 * 1000,
  /**
   * Newest final write must fall inside this window. Twelve hours lets the
   * Sunday midday pass still see late Saturday finals.
   */
  lookbackMs: 12 * 60 * 60 * 1000,
  maxTweetLength: 280,
} as const;

export type ShockTweetConfig = typeof SHOCK_TWEET_CONFIG;

export const SHOCK_REASON = {
  dogCoverLowPct: "dog_cover_low_pct",
  dogWinLowPct: "dog_win_low_pct",
  favoriteFailHighPct: "favorite_fail_high_pct",
} as const;

export type ShockTweetStatus = "pending" | "posted" | "skipped" | "failed";
export type WinnerSide = "home" | "away" | "push";

export interface LeagueGameSample {
  gameId: string;
  espnEventId?: string;
  homeTeamId: string;
  awayTeamId: string;
  homeTeamName: string;
  awayTeamName: string;
  homeTeamAbbreviation?: string;
  awayTeamAbbreviation?: string;
  spread: number;
  spreadTeamId: string;
  status: "scheduled" | "inProgress" | "final";
  homeScore: number | null;
  awayScore: number | null;
  pickMode: PickMode;
  /** Team ids for this game. No user, league, or commissioner ids. */
  pickedTeamIds: string[];
  /** Slate game `updateTime`. Null when the write clock is unknown. */
  finalizedAtMs: number | null;
}

export interface ShockTweetDraft {
  id: string;
  espnEventId?: string;
  gameKey: string;
  homeTeamName: string;
  awayTeamName: string;
  homeScore: number;
  awayScore: number;
  spread: number;
  spreadTeamId: string;
  mode: PickMode;
  pickCount: number;
  homePickCount: number;
  awayPickCount: number;
  homePickPct: number;
  awayPickPct: number;
  coveredTeamId: string | null;
  winnerSide: WinnerSide;
  shockReason: string;
  draftTweet: string;
  status: "pending" | "skipped";
  skipReason?: string;
}

export interface ShockEvaluation {
  drafts: ShockTweetDraft[];
  /** Finals whose newest write is still inside the settle delay. */
  deferred: number;
  /** In-window finals we would not score (split line, or no team names). */
  held: number;
}

export interface ShockRunResult {
  created: number;
  unchanged: number;
  pending: number;
  skipped: number;
  deferred: number;
  held: number;
}

export interface ShockTweetStore {
  get(id: string): Promise<{ status?: string } | null>;
  create(draft: ShockTweetDraft): Promise<"created" | "exists">;
}

interface SideTally {
  home: number;
  away: number;
  total: number;
}

interface FavoriteSide {
  favoriteTeamId: string;
  dogTeamId: string;
}

export function isShockTweetWindow(now: Date): boolean {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: SHOCK_TWEET_TIME_ZONE,
    weekday: "short",
    hour: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const weekday = parts.find((part) => part.type === "weekday")?.value;
  const hour = Number(parts.find((part) => part.type === "hour")?.value);
  if (!Number.isFinite(hour)) return false;
  if (weekday === "Sat") return hour >= 15 && hour <= 23;
  if (weekday === "Sun") return hour === 12;
  return false;
}

export function shockGameKey(
  sample: Pick<LeagueGameSample, "espnEventId" | "homeTeamId" | "awayTeamId">
): string {
  const espn = sample.espnEventId?.trim();
  const raw = espn ? espn : `${sample.awayTeamId}@${sample.homeTeamId}`;
  return raw.replace(/[/\s]+/g, "_");
}

export function shockTweetId(gameKey: string, mode: PickMode): string {
  return `${gameKey}_${mode}`;
}

/** Integer percent 0–100. Threshold checks use the unrounded ratio instead. */
export function roundedPickPct(count: number, total: number): number {
  if (total <= 0) return 0;
  return Math.round((count / total) * 100);
}

export function tallySidePicks(
  pickedTeamIds: readonly string[],
  homeTeamId: string,
  awayTeamId: string
): SideTally {
  let home = 0;
  let away = 0;
  for (const teamId of pickedTeamIds) {
    if (teamId === homeTeamId) home += 1;
    else if (teamId === awayTeamId) away += 1;
  }
  return { home, away, total: home + away };
}

/**
 * Count picks for one slate game. When `memberIds` is non-empty, only that
 * roster counts — same boundary as scoring. Blank picks are ignored via
 * `pickedTeamId`.
 */
export function collectPickedTeamIds(
  pickDocs: Array<{ userId: string; picks: unknown }>,
  gameId: string,
  memberIds: readonly string[] | undefined
): string[] {
  const roster = (memberIds ?? []).filter((id) => id.trim().length > 0);
  const allowed = roster.length > 0 ? new Set(roster) : null;
  const teams: string[] = [];
  for (const doc of pickDocs) {
    if (allowed && !allowed.has(doc.userId)) continue;
    if (!doc.picks || typeof doc.picks !== "object" || Array.isArray(doc.picks)) continue;
    const team = pickedTeamId(doc.picks as Record<string, string>, gameId);
    if (team) teams.push(team);
  }
  return teams;
}

export function parseLeagueGameSample(input: {
  gameId: string;
  data: Record<string, unknown>;
  pickMode: PickMode;
  pickedTeamIds: string[];
  finalizedAtMs: number | null;
}): LeagueGameSample | null {
  const homeTeamId = readString(input.data.homeTeamId);
  const awayTeamId = readString(input.data.awayTeamId);
  const spreadTeamId = readString(input.data.spreadTeamId);
  const status = input.data.status;
  if (!homeTeamId || !awayTeamId || !spreadTeamId) return null;
  if (status !== "scheduled" && status !== "inProgress" && status !== "final") return null;
  if (typeof input.data.spread !== "number" || !Number.isFinite(input.data.spread)) return null;
  return {
    gameId: input.gameId,
    espnEventId: readString(input.data.espnEventId) ?? undefined,
    homeTeamId,
    awayTeamId,
    homeTeamName: readString(input.data.homeTeamName) ?? "",
    awayTeamName: readString(input.data.awayTeamName) ?? "",
    homeTeamAbbreviation: readString(input.data.homeTeamAbbreviation) ?? undefined,
    awayTeamAbbreviation: readString(input.data.awayTeamAbbreviation) ?? undefined,
    spread: input.data.spread,
    spreadTeamId,
    status,
    homeScore: finiteNumber(input.data.homeScore),
    awayScore: finiteNumber(input.data.awayScore),
    pickMode: input.pickMode,
    pickedTeamIds: input.pickedTeamIds,
    finalizedAtMs: input.finalizedAtMs,
  };
}

/**
 * Dog outcome wins when both heuristics match, because a dog cover at ≤35%
 * already implies the public was on the favorite. Favorite-fail is what
 * remains for a push (or a straight-up loss that did not also qualify as a
 * low dog share).
 */
export function classifyShock(
  input: {
    mode: PickMode;
    dogPickCount: number;
    favoritePickCount: number;
    pickCount: number;
    coveredTeamId: string | null;
    dogTeamId: string;
    favoriteTeamId: string;
  },
  config: ShockTweetConfig = SHOCK_TWEET_CONFIG
): string | null {
  if (input.pickCount <= 0) return null;
  const dogShare = (input.dogPickCount / input.pickCount) * 100;
  const favoriteShare = (input.favoritePickCount / input.pickCount) * 100;
  const dogWon = input.coveredTeamId === input.dogTeamId;
  // Straight up, "the favorite lost" means the dog won. A tie is a push.
  // ATS, failing to cover includes a push and a dog cover.
  const favoriteFailed =
    input.mode === "straightUp" ? dogWon : input.coveredTeamId !== input.favoriteTeamId;
  if (dogWon && dogShare <= config.dogPickPctMax) {
    return input.mode === "straightUp" ? SHOCK_REASON.dogWinLowPct : SHOCK_REASON.dogCoverLowPct;
  }
  if (favoriteFailed && favoriteShare >= config.favoritePickPctMin) {
    return SHOCK_REASON.favoriteFailHighPct;
  }
  return null;
}

export function buildDraftTweet(input: {
  homeTeamName: string;
  awayTeamName: string;
  homeTeamAbbreviation?: string;
  awayTeamAbbreviation?: string;
  homeScore: number;
  awayScore: number;
  clause: string;
  maxLength?: number;
}): string {
  const maxLength = input.maxLength ?? SHOCK_TWEET_CONFIG.maxTweetLength;
  const full = formatFinalLine(
    input.homeTeamName,
    input.awayTeamName,
    input.homeScore,
    input.awayScore,
    input.clause
  );
  if (full.length <= maxLength) return full;
  const home = input.homeTeamAbbreviation?.trim() || input.homeTeamName;
  const away = input.awayTeamAbbreviation?.trim() || input.awayTeamName;
  const short = formatFinalLine(home, away, input.homeScore, input.awayScore, input.clause);
  if (short.length <= maxLength) return short;
  return `${short.slice(0, maxLength - 1).trimEnd()}…`;
}

export function evaluateShockTweets(
  samples: readonly LeagueGameSample[],
  nowMs: number,
  config: ShockTweetConfig = SHOCK_TWEET_CONFIG
): ShockEvaluation {
  const groups = new Map<string, LeagueGameSample[]>();
  for (const sample of samples) {
    if (!isFinalWithScores(sample)) continue;
    const key = `${shockGameKey(sample)}_${sample.pickMode}`;
    const bucket = groups.get(key);
    if (bucket) bucket.push(sample);
    else groups.set(key, [sample]);
  }

  const drafts: ShockTweetDraft[] = [];
  let deferred = 0;
  let held = 0;

  for (const group of groups.values()) {
    const clock = groupClock(group, nowMs, config);
    if (clock === "deferred") {
      deferred += 1;
      continue;
    }
    if (clock === "stale") continue;

    const built = buildGroupDraft(group, config);
    if (built === "held") {
      held += 1;
      continue;
    }
    if (built) drafts.push(built);
  }

  drafts.sort((a, b) => a.id.localeCompare(b.id));
  return { drafts, deferred, held };
}

export async function runShockTweetDetection(options?: {
  nowMs?: number;
  samples?: LeagueGameSample[];
  store?: ShockTweetStore;
  config?: ShockTweetConfig;
}): Promise<ShockRunResult> {
  const config = options?.config ?? SHOCK_TWEET_CONFIG;
  const nowMs = options?.nowMs ?? Date.now();
  const samples = options?.samples ?? (await loadLeagueGameSamples(nowMs, config));
  const store = options?.store ?? firestoreShockTweetStore();
  const evaluation = evaluateShockTweets(samples, nowMs, config);

  let created = 0;
  let unchanged = 0;
  let pending = 0;
  let skipped = 0;

  for (const draft of evaluation.drafts) {
    const existing = await store.get(draft.id);
    if (existing) {
      unchanged += 1;
      continue;
    }
    const outcome = await store.create(draft);
    if (outcome === "exists") {
      unchanged += 1;
      continue;
    }
    created += 1;
    if (draft.status === "pending") pending += 1;
    else skipped += 1;
    logger.info("shock tweet drafted", {
      id: draft.id,
      status: draft.status,
      shockReason: draft.shockReason,
      skipReason: draft.skipReason ?? null,
      pickCount: draft.pickCount,
      mode: draft.mode,
    });
  }

  return {
    created,
    unchanged,
    pending,
    skipped,
    deferred: evaluation.deferred,
    held: evaluation.held,
  };
}

export async function loadLeagueGameSamples(
  nowMs: number,
  config: ShockTweetConfig = SHOCK_TWEET_CONFIG
): Promise<LeagueGameSample[]> {
  const firestore = admin.firestore();
  const groups = await firestore.collection("groups").get();
  const seasonFloor = easternYmd(new Date(nowMs)).year - 1;
  const samples: LeagueGameSample[] = [];

  for (const groupDoc of groups.docs) {
    try {
      const group = groupDoc.data();
      const rules = group.rules;
      const leaguePickMode =
        rules && typeof rules === "object" ? (rules as { pickMode?: unknown }).pickMode : undefined;
      const memberIds = Array.isArray(group.memberIds)
        ? group.memberIds.filter((id): id is string => typeof id === "string")
        : undefined;
      const weeks = await groupDoc.ref
        .collection("weeks")
        .where("status", "in", ["picking", "locked", "scored"])
        .get();

      for (const weekDoc of weeks.docs) {
        const week = weekDoc.data();
        if (!weekWorthReading(week, nowMs, config.lookbackMs, seasonFloor)) continue;
        const pickMode = resolveWeekPickMode(week.pickMode, leaguePickMode);
        const [gamesSnap, picksSnap] = await Promise.all([
          weekDoc.ref.collection("games").get(),
          weekDoc.ref.collection("picks").get(),
        ]);
        const pickDocs = picksSnap.docs.map((doc) => ({
          userId: doc.id,
          picks: doc.data().picks,
        }));
        for (const gameDoc of gamesSnap.docs) {
          const sample = parseLeagueGameSample({
            gameId: gameDoc.id,
            data: gameDoc.data(),
            pickMode,
            pickedTeamIds: collectPickedTeamIds(pickDocs, gameDoc.id, memberIds),
            finalizedAtMs: gameDoc.updateTime ? gameDoc.updateTime.toMillis() : null,
          });
          if (sample) samples.push(sample);
        }
      }
    } catch (err) {
      logger.error("shock tweets failed to read group", { groupId: groupDoc.id, err });
    }
  }

  return samples;
}

export const detectShockTweets = onSchedule(
  {
    schedule: SHOCK_TWEET_SCHEDULE,
    timeZone: SHOCK_TWEET_TIME_ZONE,
    timeoutSeconds: 180,
  },
  async () => {
    const now = new Date();
    if (!isShockTweetWindow(now)) {
      logger.info("detectShockTweets outside window", { now: now.toISOString() });
      return;
    }
    const result = await runShockTweetDetection({ nowMs: now.getTime() });
    logger.info("detectShockTweets complete", result);
  }
);

/** Manual run. Ignores the Saturday/Sunday window. Requires the admin claim. */
export const runDetectShockTweets = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  if (request.auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "This account is not authorized.");
  }
  const result = await runShockTweetDetection();
  logger.info("runDetectShockTweets", { uid: request.auth.uid, ...result });
  return result;
});

function firestoreShockTweetStore(): ShockTweetStore {
  const collection = () => admin.firestore().collection("shockTweets");
  return {
    async get(id) {
      const snap = await collection().doc(id).get();
      if (!snap.exists) return null;
      const status = snap.data()?.status;
      return { status: typeof status === "string" ? status : undefined };
    },
    async create(draft) {
      try {
        await collection().doc(draft.id).create(draftToFirestore(draft));
        return "created";
      } catch (err) {
        if (isAlreadyExists(err)) return "exists";
        throw err;
      }
    },
  };
}

function draftToFirestore(draft: ShockTweetDraft): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    id: draft.id,
    gameKey: draft.gameKey,
    homeTeamName: draft.homeTeamName,
    awayTeamName: draft.awayTeamName,
    homeScore: draft.homeScore,
    awayScore: draft.awayScore,
    spread: draft.spread,
    spreadTeamId: draft.spreadTeamId,
    mode: draft.mode,
    pickCount: draft.pickCount,
    homePickCount: draft.homePickCount,
    awayPickCount: draft.awayPickCount,
    homePickPct: draft.homePickPct,
    awayPickPct: draft.awayPickPct,
    coveredTeamId: draft.coveredTeamId,
    winnerSide: draft.winnerSide,
    shockReason: draft.shockReason,
    draftTweet: draft.draftTweet,
    status: draft.status,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (draft.espnEventId) payload.espnEventId = draft.espnEventId;
  if (draft.skipReason) payload.skipReason = draft.skipReason;
  return payload;
}

function buildGroupDraft(
  group: readonly LeagueGameSample[],
  config: ShockTweetConfig
): ShockTweetDraft | "held" | null {
  const canonical = chooseCanonical(group);
  if (!scoresAgree(group) || !teamsAgree(group)) return "held";

  const homeScore = canonical.homeScore;
  const awayScore = canonical.awayScore;
  if (homeScore == null || awayScore == null) return "held";

  const covers = group.map((sample) =>
    coveredTeamId(asSlateGame(sample), homeScore, awayScore, sample.pickMode)
  );
  if (!coversAgree(covers)) return "held";

  const favorites = group.map((sample) => favoriteSide(sample));
  const sides = favorites.filter((side): side is FavoriteSide => side != null);
  if (sides.length === 0) return null;
  if (sides.length !== group.length) return "held";
  const favorite = sides[0];
  if (sides.some((side) => side.favoriteTeamId !== favorite.favoriteTeamId)) return "held";

  const tally = group.reduce<SideTally>(
    (sum, sample) => {
      const side = tallySidePicks(sample.pickedTeamIds, canonical.homeTeamId, canonical.awayTeamId);
      return {
        home: sum.home + side.home,
        away: sum.away + side.away,
        total: sum.total + side.total,
      };
    },
    { home: 0, away: 0, total: 0 }
  );

  const covered = covers[0] ?? null;
  const dogPickCount = favorite.dogTeamId === canonical.homeTeamId ? tally.home : tally.away;
  const favoritePickCount =
    favorite.favoriteTeamId === canonical.homeTeamId ? tally.home : tally.away;
  const shockReason = classifyShock(
    {
      mode: canonical.pickMode,
      dogPickCount,
      favoritePickCount,
      pickCount: tally.total,
      coveredTeamId: covered,
      dogTeamId: favorite.dogTeamId,
      favoriteTeamId: favorite.favoriteTeamId,
    },
    config
  );
  if (!shockReason) return null;

  const homeTeamName = teamLabel(canonical.homeTeamName, canonical.homeTeamAbbreviation);
  const awayTeamName = teamLabel(canonical.awayTeamName, canonical.awayTeamAbbreviation);
  if (!homeTeamName || !awayTeamName) return "held";

  const homePickPct = roundedPickPct(tally.home, tally.total);
  const awayPickPct = roundedPickPct(tally.away, tally.total);
  const dogPct = roundedPickPct(dogPickCount, tally.total);
  const favoritePct = roundedPickPct(favoritePickCount, tally.total);
  const favoriteName =
    favorite.favoriteTeamId === canonical.homeTeamId ? homeTeamName : awayTeamName;
  const clause = draftClause({
    shockReason,
    mode: canonical.pickMode,
    dogPct,
    dogPickCount,
    favoritePct,
    favoritePickCount,
    favoriteName,
    pickCount: tally.total,
  });
  const draftTweet = buildDraftTweet({
    homeTeamName,
    awayTeamName,
    homeTeamAbbreviation: canonical.homeTeamAbbreviation,
    awayTeamAbbreviation: canonical.awayTeamAbbreviation,
    homeScore,
    awayScore,
    clause,
    maxLength: config.maxTweetLength,
  });

  const belowMin = tally.total < config.minPickCount;
  const gameKey = shockGameKey(canonical);
  const draft: ShockTweetDraft = {
    id: shockTweetId(gameKey, canonical.pickMode),
    gameKey,
    homeTeamName,
    awayTeamName,
    homeScore,
    awayScore,
    spread: canonical.spread,
    spreadTeamId: canonical.spreadTeamId,
    mode: canonical.pickMode,
    pickCount: tally.total,
    homePickCount: tally.home,
    awayPickCount: tally.away,
    homePickPct,
    awayPickPct,
    coveredTeamId: covered,
    winnerSide: winnerSide(covered, canonical.homeTeamId, canonical.awayTeamId),
    shockReason,
    draftTweet,
    status: belowMin ? "skipped" : "pending",
  };
  if (canonical.espnEventId?.trim()) draft.espnEventId = canonical.espnEventId.trim();
  if (belowMin) draft.skipReason = "min_sample";
  return draft;
}

function draftClause(input: {
  shockReason: string;
  mode: PickMode;
  dogPct: number;
  dogPickCount: number;
  favoritePct: number;
  favoritePickCount: number;
  favoriteName: string;
  pickCount: number;
}): string {
  if (
    input.shockReason === SHOCK_REASON.dogCoverLowPct ||
    input.shockReason === SHOCK_REASON.dogWinLowPct
  ) {
    const outcome = input.mode === "straightUp" ? "won" : "covered";
    return `Only ${input.dogPct}% of Pickems picks (${input.dogPickCount}/${input.pickCount}) took the dog — and they ${outcome}.`;
  }
  const outcome = input.mode === "straightUp" ? "lost" : "didn't cover";
  return `${input.favoritePct}% of Pickems picks (${input.favoritePickCount}/${input.pickCount}) took ${input.favoriteName} — and they ${outcome}.`;
}

function formatFinalLine(
  homeName: string,
  awayName: string,
  homeScore: number,
  awayScore: number,
  clause: string
): string {
  const matchup =
    awayScore > homeScore
      ? `${awayName} ${awayScore}, ${homeName} ${homeScore}`
      : `${homeName} ${homeScore}, ${awayName} ${awayScore}`;
  return `FINAL: ${matchup}. ${clause}`;
}

function groupClock(
  group: readonly LeagueGameSample[],
  nowMs: number,
  config: ShockTweetConfig
): "ready" | "deferred" | "stale" {
  if (group.some((sample) => sample.finalizedAtMs == null)) return "deferred";
  const newest = Math.max(...group.map((sample) => sample.finalizedAtMs as number));
  const age = nowMs - newest;
  if (age < config.settleDelayMs) return "deferred";
  if (age > config.lookbackMs) return "stale";
  return "ready";
}

function isFinalWithScores(sample: LeagueGameSample): boolean {
  return sample.status === "final" && sample.homeScore != null && sample.awayScore != null;
}

function scoresAgree(group: readonly LeagueGameSample[]): boolean {
  const home = group[0]?.homeScore;
  const away = group[0]?.awayScore;
  return group.every((sample) => sample.homeScore === home && sample.awayScore === away);
}

function teamsAgree(group: readonly LeagueGameSample[]): boolean {
  const home = group[0]?.homeTeamId;
  const away = group[0]?.awayTeamId;
  return group.every((sample) => sample.homeTeamId === home && sample.awayTeamId === away);
}

function coversAgree(covers: Array<string | null>): boolean {
  return covers.every((cover) => cover === covers[0]);
}

function favoriteSide(sample: LeagueGameSample): FavoriteSide | null {
  if (!(Math.abs(sample.spread) > 0)) return null;
  if (sample.spreadTeamId === sample.homeTeamId) {
    return { favoriteTeamId: sample.homeTeamId, dogTeamId: sample.awayTeamId };
  }
  if (sample.spreadTeamId === sample.awayTeamId) {
    return { favoriteTeamId: sample.awayTeamId, dogTeamId: sample.homeTeamId };
  }
  return null;
}

function chooseCanonical(group: readonly LeagueGameSample[]): LeagueGameSample {
  return [...group].sort((a, b) => {
    const byPicks = b.pickedTeamIds.length - a.pickedTeamIds.length;
    if (byPicks !== 0) return byPicks;
    return a.gameId.localeCompare(b.gameId);
  })[0];
}

function winnerSide(
  covered: string | null,
  homeTeamId: string,
  awayTeamId: string
): WinnerSide {
  if (covered === homeTeamId) return "home";
  if (covered === awayTeamId) return "away";
  return "push";
}

function teamLabel(name: string, abbreviation?: string): string | null {
  const full = name.trim();
  if (full) return full;
  const short = abbreviation?.trim();
  return short ? short : null;
}

function asSlateGame(sample: LeagueGameSample): SlateGameDoc {
  return {
    id: sample.gameId,
    espnEventId: sample.espnEventId ?? sample.gameId,
    homeTeamId: sample.homeTeamId,
    awayTeamId: sample.awayTeamId,
    spread: sample.spread,
    spreadTeamId: sample.spreadTeamId,
    status: sample.status,
    homeScore: sample.homeScore,
    awayScore: sample.awayScore,
  };
}

function weekWorthReading(
  week: FirebaseFirestore.DocumentData,
  nowMs: number,
  lookbackMs: number,
  seasonFloor: number
): boolean {
  const seasonYear = week.seasonYear;
  if (typeof seasonYear === "number" && seasonYear < seasonFloor) return false;
  if (week.status === "picking" || week.status === "locked") return true;
  if (week.status !== "scored") return false;
  const scoredAt = toMillis(week.scoredAt);
  if (scoredAt == null) return false;
  return nowMs - scoredAt <= lookbackMs;
}

function readString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function isAlreadyExists(err: unknown): boolean {
  const code = (err as { code?: number | string }).code;
  return code === 6 || code === "already-exists" || code === "ALREADY_EXISTS";
}
