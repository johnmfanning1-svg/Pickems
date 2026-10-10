import { resolvePickMode, type PickMode } from "./scoring";

/**
 * Roast copy for a game-final push.
 *
 * Thresholds (owner-editable):
 * - blowout / dominant: 14 points (ATS = cover margin, Straight Up = score margin)
 * - bad beat / backdoor: more than 0 and at most 3
 * - the hook: an ATS miss or cover of exactly 0.5
 * - upset loss: picked a favorite of 14+ that lost the game outright
 * - upset win: picked an underdog of 7+ that won the game outright
 * - blown lead: picked team led at halftime or after 3 quarters, then lost outright
 * - late flip: trailing the bet at the latest checkpoint (end of Q3, else halftime)
 *   and the final margin is under 14 — counts as a backdoor
 *
 * Priority, losses: blown lead, upset loss, bad beat, blowout, plain.
 * Priority, wins: called the upset, backdoor, dominant, plain.
 * A missing score, spread, or period list drops to the plain win/loss/push pool.
 */

export const THRESHOLDS = {
  blowout: 14,
  badBeat: 3,
  hook: 0.5,
  bigFavorite: 14,
  upsetDog: 7,
  dominant: 14,
  backdoor: 3,
} as const;

export const MAX_PUSH_TITLE_LENGTH = 40;
export const MAX_PUSH_BODY_LENGTH = 120;

export type GameFinalResult = "covered" | "missed" | "push";

export type GameFinalScenario =
  | "blowout_loss"
  | "bad_beat"
  | "upset_loss"
  | "blown_lead"
  | "plain_loss"
  | "upset_win"
  | "backdoor_win"
  | "dominant_win"
  | "plain_win"
  | "push";

export interface GameFinalCopy {
  title: string;
  body: string;
}

export interface GameFinalClassification {
  scenario: GameFinalScenario;
  result: GameFinalResult;
  pickMode: PickMode;
  hook: boolean;
  /** Positive when the pick won the bet. Null when the margin cannot be computed. */
  signedMargin: number | null;
  blownLead: boolean;
  lateFlip: boolean;
}

export interface LastSpicyGameFinal {
  key: string;
  title: string;
  body: string;
}

/** Fields the classifier reads. Anything unusable is ignored. */
export interface GameFinalCopyInput {
  userId?: unknown;
  gameId?: unknown;
  groupId?: unknown;
  pickMode?: unknown;
  /** Resolved preference. Only a real `false` turns the roast off. */
  spicyAlerts?: unknown;
  pickedTeamId?: unknown;
  homeTeamId?: unknown;
  awayTeamId?: unknown;
  homeTeamName?: unknown;
  awayTeamName?: unknown;
  homeTeamAbbreviation?: unknown;
  awayTeamAbbreviation?: unknown;
  homeScore?: unknown;
  awayScore?: unknown;
  spread?: unknown;
  spreadTeamId?: unknown;
  winnerTeamId?: unknown;
  /** Points per period, or a cumulative running total (detected against the final). */
  homeLineScores?: unknown;
  awayLineScores?: unknown;
  halftimeHomeScore?: unknown;
  halftimeAwayScore?: unknown;
  afterThreeHomeScore?: unknown;
  afterThreeAwayScore?: unknown;
  previous?: unknown;
}

type ModeGate = "ats" | "su" | "hook" | "ats-hook";

interface PooledLine {
  text: string;
  when?: ModeGate;
}

/**
 * `{team}` picked side, `{opp}` the other side, `{margin}` miss/cover size,
 * `{spread}` pregame number, `{score}` final, `{missedBy}` / `{wonBy}` mode phrase.
 * `{MissedBy}` and `{WonBy}` are the capitalized forms.
 */
export const LINE_POOLS: Record<GameFinalScenario, readonly PooledLine[]> = {
  blowout_loss: [
    { text: "Horrible pick." },
    { text: "{team} {missedBy} {margin}. The group chat is already typing." },
    { text: "{score}. You picked {team}. We're bringing this up at Thanksgiving." },
    { text: "You lost the argument with {opp} by {margin}." },
    { text: "A {margin}-point miss. Were you watching a different sport?" },
    { text: "Off by {margin}. The spreadsheet is ashamed of you." },
    { text: "This bet was over early and so were you." },
    { text: "You called {team} a lock. It was a lock. For {opp}." },
  ],
  bad_beat: [
    { text: "{team} {missedBy} {margin}. Brutal." },
    { text: "Short by {margin}. Hang the screenshot in the group chat." },
    { text: "Half a point. {opp} sends their regards and the receipt.", when: "ats-hook" },
  ],
  upset_loss: [
    { text: "What were you thinking?" },
    { text: "You took a {spread}-point favorite and they lost outright. Delete the app." },
    { text: "A {spread}-point favorite. Outright. The group chat needs a minute." },
    { text: "{opp} just beat your {spread}-point lock. The spread was a suggestion." },
    { text: "You faded the dog. The dog ate the {spread} and your week." },
    { text: "Favorite by {spread}. Final {score}. Put the phone in the other room." },
    { text: "Vegas spotted everybody {spread} and {team} still found a way." },
    { text: "Big favorite. Straight-up loss. We're printing the shirts." },
    { text: "{opp} as a {spread}-point dog. You picked the other side. Incredible." },
  ],
  blown_lead: [
    { text: "{team} had the lead and returned it like a library book." },
    { text: "Up at the half. Lost the game. Damn." },
    { text: "You were winning, and then everyone remembered who you picked." },
    { text: "Blown lead. {team} looked at the clock and got generous." },
    { text: "Halftime was the peak. Then a cliff with your name on it." },
    { text: "The lead was right there. {team} handed it to {opp} with both hands." },
    { text: "Up late, lost anyway. Your pick has commitment issues." },
  ],
  plain_loss: [
    { text: "Hope you didn't put money on that." },
    { text: "What were you thinking?" },
    { text: "Horrible pick." },
    { text: "{team} didn't get it done. {score}. We'll allow one excuse." },
    { text: "{opp} gets the last word. The group chat already has the meme." },
    { text: "Not a blowout. Not a heartbreaker. Just a regular bad idea." },
    { text: "You picked {team}. The bet did not. Teamwork." },
    { text: "Add it to the pile. We'll alphabetize later." },
    { text: "{team} sends their regrets. They will not be covering your tab." },
    { text: "Clean miss. No tragedy. Just you and the consequences." },
    { text: "{score}. Wrong side. See you next Saturday." },
  ],
  upset_win: [
    { text: "{team} was a {spread}-point dog and won outright. You're unbearable now." },
    { text: "Called the upset. {opp} was laying {spread} and still lost." },
    { text: "You picked a {spread}-point dog and they actually won. Disgusting. Respect." },
    { text: "{score}. The favorite was {opp}. You said no, and you were right." },
    { text: "Upset by {spread}. Do not be normal about this." },
    { text: "Vegas had {team} down {spread}. You had a feeling. Annoyingly, it was right." },
    { text: "You brought a {spread}-point dog to a fight and the dog won." },
    { text: "A {spread}-point upset. The group chat owes you a drink it will not buy." },
    { text: "Screenshot this before it starts feeling like luck. {team} outright." },
    { text: "{team} outright. The {spread} was the other way. Absurd." },
    { text: "Called it. {team} just knocked off {opp} like the line was a rumor." },
    { text: "Underdog by {spread}. Winner by nerve. Mostly yours." },
  ],
  backdoor_win: [
    { text: "{WonBy} {margin}. You did nothing and still got paid." },
    { text: "{team} snuck through by {margin}. Take the win. Do not explain it." },
    { text: "You were dead, then one score happened. We'll allow it." },
    { text: "By {margin}, the right way. The football gods got bored of hurting you." },
    { text: "{score}. Ugly win. Ugly still cashes." },
    { text: "This one was a gift. Say thank you and log off." },
    { text: "{WonBy} {margin}. Call it a plan if you need to sleep." },
    { text: "{opp} had you, and then they didn't." },
    { text: "{team} by {margin}. You supplied the confidence. They supplied the points." },
    { text: "Late and lucky. The best kind of correct." },
    { text: "Don't narrate the path. Just take the {margin}." },
    { text: "Backdoor cover. You did nothing and still got paid.", when: "ats" },
    { text: "Squeaked by {margin}. You did nothing and still get to gloat.", when: "su" },
  ],
  dominant_win: [
    { text: "{team} {wonBy} {margin}. Were you even stressed?" },
    { text: "Dominant. {score}. Try to be cool about it. You won't." },
    { text: "{WonBy} {margin}. The other sideline needs a minute." },
    { text: "{opp} never had a chance. You knew. Unfortunately we all know you knew." },
    { text: "{margin} points of pure I told you so." },
    { text: "{team} ran them off the field. This notification is just the parade." },
    { text: "That's not a close one. That's a statement. {margin}." },
    { text: "{score}. Somewhere your old losses are apologizing." },
    { text: "You picked {team} and they won like the other team owed them money." },
    { text: "{margin}. Clean. Mean. Correct." },
    { text: "The group chat went quiet and it's your fault." },
    { text: "{team} by {margin}. Lock it, print it, be annoying." },
  ],
  plain_win: [
    { text: "{team} got it done. {score}. Act like you've been here." },
    { text: "You were right. Don't let it go to your head. Too late." },
    { text: "{team} over {opp}. Normal, respectable, slightly smug." },
    { text: "Cash it. {team} handled the business." },
    { text: "Not a squeaker. Not a blowout. Just correct, which is honestly rude." },
    { text: "{score}. Your pick survived contact with the game." },
    { text: "{team} won you the square. The group chat will cope." },
    { text: "Clean win. No drama. Disappointing for everyone else." },
    { text: "You picked {team}. They won. The system works, unfortunately." },
    { text: "{opp} had a window. {team} closed it." },
    { text: "A win. A small amount of trash talk has been authorized." },
    { text: "{team}. Correct. See you next week, genius." },
  ],
  push: [
    { text: "Push. Nobody wins, which feels right for this group." },
    { text: "{score}. You get your pride back, unused." },
    { text: "{team} neither saved you nor buried you. A push." },
    { text: "No win, no loss, no bit. Incredible waste of adrenaline." },
    { text: "A push. The rare notification where you almost escape a roast." },
  ],
};

const SCENARIO_TITLE: Record<GameFinalScenario, string> = {
  blowout_loss: "Horrible pick",
  bad_beat: "So close",
  upset_loss: "Upset",
  blown_lead: "Blown lead",
  plain_loss: "Tough beat",
  upset_win: "Called it",
  backdoor_win: "Backdoor",
  dominant_win: "Dominant",
  plain_win: "You covered",
  push: "Push",
};

const SCENARIO_FALLBACK: Record<GameFinalScenario, string> = {
  blowout_loss: "Horrible pick.",
  bad_beat: "So close. Brutal.",
  upset_loss: "What were you thinking?",
  blown_lead: "Blown lead. You had it.",
  plain_loss: "Hope you didn't put money on that.",
  upset_win: "Called the upset.",
  backdoor_win: "Backdoor. You still got paid.",
  dominant_win: "Dominant. Were you even stressed?",
  plain_win: "You were right. Don't get used to it.",
  push: "Push. Nobody wins.",
};

const TOKEN = /\{(\w+)\}/g;

export function spicyGameFinalKey(groupId: string, gameId: string): string {
  return `${groupId}:${gameId}`;
}

/** Member boolean wins, then the account boolean, then on. Non-booleans are ignored. */
export function resolveSpicyAlerts(
  user: { spicyAlerts?: unknown } | null | undefined,
  member?: { spicyAlerts?: unknown } | null
): boolean {
  if (typeof member?.spicyAlerts === "boolean") return member.spicyAlerts;
  if (typeof user?.spicyAlerts === "boolean") return user.spicyAlerts;
  return true;
}

function previousFromInput(value: unknown): LastSpicyGameFinal | null {
  const record = asRecord(value);
  const key = asNonEmptyString(record.key);
  const title = asNonEmptyString(record.title);
  const body = asNonEmptyString(record.body);
  if (!key || !title || !body) return null;
  return { key, title, body };
}

export function readLastSpicyGameFinal(data: unknown): LastSpicyGameFinal | null {
  const record = asRecord(data);
  const key = asNonEmptyString(record.lastSpicyGameFinalKey);
  const title = asNonEmptyString(record.lastSpicyGameFinalTitle);
  const body = asNonEmptyString(record.lastSpicyGameFinalBody);
  if (!key || !title || !body) return null;
  return { key, title, body };
}

/**
 * Pull period scores off a stored game doc. Known aliases are accepted.
 * Stored slate docs today do not write these; a later final pass may.
 */
export function periodInputFromGame(game: unknown): Pick<
  GameFinalCopyInput,
  | "homeLineScores"
  | "awayLineScores"
  | "halftimeHomeScore"
  | "halftimeAwayScore"
  | "afterThreeHomeScore"
  | "afterThreeAwayScore"
> {
  const record = asRecord(game);
  const nested = asRecord(record.linescores);
  return {
    homeLineScores: firstDefined(record.homeLineScores, record.homeLinescores, nested.home),
    awayLineScores: firstDefined(record.awayLineScores, record.awayLinescores, nested.away),
    halftimeHomeScore: firstDefined(record.halftimeHomeScore, record.homeHalftimeScore),
    halftimeAwayScore: firstDefined(record.halftimeAwayScore, record.awayHalftimeScore),
    afterThreeHomeScore: firstDefined(record.afterThreeHomeScore, record.homeScoreAfterThree),
    afterThreeAwayScore: firstDefined(record.afterThreeAwayScore, record.awayScoreAfterThree),
  };
}

export function classifyGameFinal(input?: GameFinalCopyInput | null): GameFinalClassification {
  try {
    return classifyRecord(asRecord(input));
  } catch {
    return {
      scenario: "push",
      result: "push",
      pickMode: "ats",
      hook: false,
      signedMargin: null,
      blownLead: false,
      lateFlip: false,
    };
  }
}

export function gameFinalPushCopy(input?: GameFinalCopyInput | null): GameFinalCopy {
  try {
    return buildCopy(asRecord(input));
  } catch {
    return { title: "Push", body: "AWAY @ HOME is final." };
  }
}

/** Every line a scenario can send for this input, in pool order. For tests and review. */
export function renderScenarioLines(
  scenario: GameFinalScenario,
  input?: GameFinalCopyInput | null,
  options?: { hook?: boolean }
): string[] {
  try {
    const record = asRecord(input);
    const facts = buildFacts(record, classifyRecord(record));
    const hook = options?.hook ?? facts.hook;
    return dedupe(applicableLines(scenario, facts.pickMode, hook).map((line) => fillLine(line.text, facts)));
  } catch {
    return [];
  }
}

/** FNV-1a. Stable across processes so a retry hashes to the same line. */
export function stableHash(value: string): number {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

interface Facts {
  pickMode: PickMode;
  hook: boolean;
  team: string;
  opp: string;
  margin: string | null;
  spread: string | null;
  score: string | null;
  missedBy: string;
  wonBy: string;
}

function buildCopy(record: Record<string, unknown>): GameFinalCopy {
  const classified = classifyRecord(record);
  if (record.spicyAlerts === false) return plainCopy(record, classified);

  const previous = previousFromInput(record.previous);
  const key = spicyGameFinalKey(asString(record.groupId), asString(record.gameId));
  if (previous && previous.key === key) {
    return { title: clipTitle(previous.title), body: clipBody(previous.body) };
  }

  const facts = buildFacts(record, classified);
  const previousBody = previous?.body ?? null;
  const rendered = filledLines(classified.scenario, facts, facts.hook);
  let body = pickFromPool(
    rendered.length > 0 ? rendered : [SCENARIO_FALLBACK[classified.scenario]],
    asString(record.userId),
    asString(record.gameId),
    previousBody
  );
  // A one-line hook pool cannot rotate. Step once to the non-hook lines, then the
  // scenario fallback. Never spin.
  if (previousBody && body === previousBody && facts.hook && rendered.length <= 1) {
    const alternate = filledLines(classified.scenario, facts, false).filter((line) => line !== previousBody);
    if (alternate.length > 0) {
      body = pickFromPool(alternate, asString(record.userId), asString(record.gameId), previousBody);
    } else {
      const fallback = SCENARIO_FALLBACK[classified.scenario];
      if (fallback !== previousBody) body = fallback;
    }
  }
  return { title: clipTitle(titleFor(classified)), body: clipBody(body) };
}

function plainCopy(record: Record<string, unknown>, classified: GameFinalClassification): GameFinalCopy {
  const away = typeof record.awayTeamAbbreviation === "string" ? record.awayTeamAbbreviation : "AWAY";
  const home = typeof record.homeTeamAbbreviation === "string" ? record.homeTeamAbbreviation : "HOME";
  const title =
    classified.result === "covered"
      ? classified.pickMode === "straightUp"
        ? "You won"
        : "You covered"
      : classified.result === "missed"
        ? "Tough beat"
        : "Push";
  return { title, body: `${away} @ ${home} is final.` };
}

function titleFor(classified: GameFinalClassification): string {
  if (classified.scenario === "plain_win" && classified.pickMode === "straightUp") return "You won";
  if (classified.scenario === "backdoor_win" && classified.pickMode === "straightUp") return "Squeaker";
  return SCENARIO_TITLE[classified.scenario];
}

function classifyRecord(record: Record<string, unknown>): GameFinalClassification {
  const pickMode = resolvePickMode(record.pickMode);
  const picked = asString(record.pickedTeamId);
  const homeId = asString(record.homeTeamId);
  const awayId = asString(record.awayTeamId);
  const homeScore = finiteNumber(record.homeScore);
  const awayScore = finiteNumber(record.awayScore);
  const spread = finiteNumber(record.spread);
  const spreadMagnitude = spread == null ? null : Math.abs(spread);
  const spreadTeamId = asString(record.spreadTeamId);
  const pickedHome = picked !== "" && picked === homeId;
  const pickedAway = picked !== "" && picked === awayId;
  const pickedKnown = pickedHome || pickedAway;

  const favoriteIsHome = spreadTeamId !== "" && spreadTeamId === homeId;
  const favoriteIsAway = spreadTeamId !== "" && spreadTeamId === awayId;
  const favoriteKnown = spreadMagnitude != null && spreadMagnitude > 0 && (favoriteIsHome || favoriteIsAway);

  let signedMargin: number | null = null;
  if (pickedKnown && homeScore != null && awayScore != null) {
    const scoreMargin = pickedHome ? homeScore - awayScore : awayScore - homeScore;
    if (pickMode === "straightUp") {
      signedMargin = scoreMargin;
    } else if (spreadMagnitude === 0) {
      signedMargin = scoreMargin;
    } else if (favoriteKnown && spreadMagnitude != null) {
      const coveringHome =
        homeScore - awayScore + (favoriteIsHome ? -spreadMagnitude : spreadMagnitude);
      signedMargin = pickedHome ? coveringHome : -coveringHome;
    }
  }

  const result = resultFrom(signedMargin, asString(record.winnerTeamId), picked);
  const lostOutright =
    pickedKnown && homeScore != null && awayScore != null && (pickedHome ? homeScore < awayScore : awayScore < homeScore);
  const wonOutright =
    pickedKnown && homeScore != null && awayScore != null && (pickedHome ? homeScore > awayScore : awayScore > homeScore);
  const pickedFavorite = favoriteKnown && spreadTeamId === picked;
  const pickedDog = favoriteKnown && spreadTeamId !== picked;

  const checkpoints = checkpointsFrom(record, homeScore, awayScore);
  const blownLead = result === "missed" && lostOutright && ledAtCheckpoint(checkpoints, pickedHome);
  const lateFlip =
    result === "covered" &&
    trailingBetAtCheckpoint(checkpoints, {
      pickMode,
      pickedHome,
      spreadMagnitude,
      favoriteIsHome,
      favoriteKnown,
    });

  const miss = signedMargin != null && signedMargin < 0 ? -signedMargin : null;
  const win = signedMargin != null && signedMargin > 0 ? signedMargin : null;
  const hook = pickMode === "ats" && miss != null && nearly(miss, THRESHOLDS.hook);
  const badBeat = miss != null && miss > 0 && miss <= THRESHOLDS.badBeat;
  const blowout = miss != null && miss >= THRESHOLDS.blowout;
  const upsetLoss =
    result === "missed" &&
    pickedFavorite &&
    lostOutright &&
    spreadMagnitude != null &&
    spreadMagnitude >= THRESHOLDS.bigFavorite;
  const upsetWin =
    result === "covered" &&
    pickedDog &&
    wonOutright &&
    spreadMagnitude != null &&
    spreadMagnitude >= THRESHOLDS.upsetDog;
  const smallWin = win != null && win > 0 && win <= THRESHOLDS.backdoor;
  const backdoor = result === "covered" && (smallWin || (lateFlip && win != null && win < THRESHOLDS.dominant));
  const dominant = win != null && win >= THRESHOLDS.dominant;

  let scenario: GameFinalScenario;
  if (result === "push") scenario = "push";
  else if (result === "missed") {
    if (blownLead) scenario = "blown_lead";
    else if (upsetLoss) scenario = "upset_loss";
    else if (badBeat) scenario = "bad_beat";
    else if (blowout) scenario = "blowout_loss";
    else scenario = "plain_loss";
  } else if (upsetWin) scenario = "upset_win";
  else if (backdoor) scenario = "backdoor_win";
  else if (dominant) scenario = "dominant_win";
  else scenario = "plain_win";

  return {
    scenario,
    result,
    pickMode,
    hook: hook && scenario === "bad_beat",
    signedMargin,
    blownLead,
    lateFlip,
  };
}

interface Checkpoint {
  home: number;
  away: number;
}

function checkpointsFrom(
  record: Record<string, unknown>,
  homeFinal: number | null,
  awayFinal: number | null
): { half: Checkpoint | null; afterThree: Checkpoint | null } {
  const homePeriods = normalizePeriods(numberList(record.homeLineScores), homeFinal);
  const awayPeriods = normalizePeriods(numberList(record.awayLineScores), awayFinal);
  const half = pair(sumFirst(homePeriods, 2), sumFirst(awayPeriods, 2)) ??
    pair(finiteNumber(record.halftimeHomeScore), finiteNumber(record.halftimeAwayScore));
  const afterThree = pair(sumFirst(homePeriods, 3), sumFirst(awayPeriods, 3)) ??
    pair(finiteNumber(record.afterThreeHomeScore), finiteNumber(record.afterThreeAwayScore));
  return { half, afterThree };
}

function ledAtCheckpoint(
  checkpoints: { half: Checkpoint | null; afterThree: Checkpoint | null },
  pickedHome: boolean
): boolean {
  return [checkpoints.half, checkpoints.afterThree].some((point) => {
    if (!point) return false;
    const ours = pickedHome ? point.home : point.away;
    const theirs = pickedHome ? point.away : point.home;
    return ours > theirs;
  });
}

function trailingBetAtCheckpoint(
  checkpoints: { half: Checkpoint | null; afterThree: Checkpoint | null },
  options: {
    pickMode: PickMode;
    pickedHome: boolean;
    spreadMagnitude: number | null;
    favoriteIsHome: boolean;
    favoriteKnown: boolean;
  }
): boolean {
  const point = checkpoints.afterThree ?? checkpoints.half;
  if (!point) return false;
  if (options.pickMode === "straightUp") {
    const ours = options.pickedHome ? point.home : point.away;
    const theirs = options.pickedHome ? point.away : point.home;
    return ours <= theirs;
  }
  if (options.spreadMagnitude == null) return false;
  if (options.spreadMagnitude > 0 && !options.favoriteKnown) return false;
  const coveringHome =
    point.home -
    point.away +
    (options.favoriteIsHome ? -options.spreadMagnitude : options.spreadMagnitude);
  const signed = options.pickedHome ? coveringHome : -coveringHome;
  return signed <= 0;
}

function resultFrom(signedMargin: number | null, winnerTeamId: string, picked: string): GameFinalResult {
  if (signedMargin != null) {
    if (nearly(signedMargin, 0)) return "push";
    return signedMargin > 0 ? "covered" : "missed";
  }
  if (winnerTeamId !== "" && picked !== "") return winnerTeamId === picked ? "covered" : "missed";
  return "push";
}

function buildFacts(record: Record<string, unknown>, classified: GameFinalClassification): Facts {
  const homeName = teamLabel(record.homeTeamName, record.homeTeamAbbreviation, "Home");
  const awayName = teamLabel(record.awayTeamName, record.awayTeamAbbreviation, "Away");
  const picked = asString(record.pickedTeamId);
  const homeId = asString(record.homeTeamId);
  const awayId = asString(record.awayTeamId);
  const pickedHome = picked !== "" && picked === homeId;
  const pickedAway = picked !== "" && picked === awayId;
  const team = pickedHome ? homeName : pickedAway ? awayName : "Your team";
  const opp = pickedHome ? awayName : pickedAway ? homeName : "the other side";
  const homeScore = finiteNumber(record.homeScore);
  const awayScore = finiteNumber(record.awayScore);
  const awayAbbr = asString(record.awayTeamAbbreviation) || awayName.slice(0, 4).toUpperCase();
  const homeAbbr = asString(record.homeTeamAbbreviation) || homeName.slice(0, 4).toUpperCase();
  const spread = finiteNumber(record.spread);
  const spreadMagnitude = spread == null ? null : Math.abs(spread);
  return {
    pickMode: classified.pickMode,
    hook: classified.hook,
    team,
    opp,
    margin: classified.signedMargin == null ? null : formatMargin(Math.abs(classified.signedMargin)),
    spread: spreadMagnitude != null && spreadMagnitude > 0 ? formatSpread(spreadMagnitude) : null,
    score:
      homeScore == null || awayScore == null
        ? null
        : `${awayAbbr} ${formatScore(awayScore)}, ${homeAbbr} ${formatScore(homeScore)}`,
    missedBy: classified.pickMode === "straightUp" ? "lost by" : "missed by",
    wonBy: classified.pickMode === "straightUp" ? "won by" : "covered by",
  };
}

function applicableLines(scenario: GameFinalScenario, mode: PickMode, hook: boolean): PooledLine[] {
  const pool = LINE_POOLS[scenario];
  if (hook) {
    const hooked = pool.filter(
      (line) => line.when === "hook" || (line.when === "ats-hook" && mode === "ats")
    );
    if (hooked.length > 0) return hooked;
  }
  return pool.filter((line) => {
    if (line.when === "ats") return mode === "ats";
    if (line.when === "su") return mode === "straightUp";
    return line.when == null;
  });
}

function filledLines(scenario: GameFinalScenario, facts: Facts, hook: boolean): string[] {
  return dedupe(applicableLines(scenario, facts.pickMode, hook).map((line) => fillLine(line.text, facts)));
}

function fillLine(template: string, facts: Facts): string | null {
  const tokens: Record<string, string | null> = {
    team: facts.team,
    opp: facts.opp,
    margin: facts.margin,
    spread: facts.spread,
    score: facts.score,
    missedBy: facts.missedBy,
    MissedBy: capitalize(facts.missedBy),
    wonBy: facts.wonBy,
    WonBy: capitalize(facts.wonBy),
  };
  let missing = false;
  const filled = template.replace(TOKEN, (whole, key: string) => {
    const value = tokens[key];
    if (value == null) {
      missing = true;
      return whole;
    }
    return value;
  });
  if (missing) return null;
  const clean = filled.replace(/\s+/g, " ").trim();
  return clean.length > 0 ? clean : null;
}

function pickFromPool(lines: string[], userId: string, gameId: string, previousBody: string | null): string {
  const pool = dedupe(lines);
  if (pool.length === 0) return "Push.";
  const index = stableHash(`${userId}:${gameId}`) % pool.length;
  // One step only. A single-line pool (the hook) returns that line; buildCopy falls back.
  if (previousBody && pool[index] === previousBody && pool.length > 1) {
    return pool[(index + 1) % pool.length];
  }
  return pool[index];
}

function normalizePeriods(scores: number[] | null, finalScore: number | null): number[] | null {
  if (!scores || scores.length === 0) return null;
  if (finalScore == null || scores.length < 2) return scores;
  const sum = scores.reduce((total, value) => total + value, 0);
  if (nearly(sum, finalScore)) return scores;
  const last = scores[scores.length - 1];
  if (nearly(last, finalScore) && sum > finalScore) {
    const deltas = [scores[0]];
    for (let i = 1; i < scores.length; i++) deltas.push(scores[i] - scores[i - 1]);
    if (deltas.some((value) => value < 0)) return scores;
    return deltas;
  }
  return scores;
}

function numberList(value: unknown): number[] | null {
  if (!Array.isArray(value) || value.length === 0) return null;
  const scores: number[] = [];
  for (const item of value) {
    const parsed = finiteNumber(item);
    if (parsed == null || parsed < 0) return null;
    scores.push(parsed);
  }
  return scores;
}

function sumFirst(scores: number[] | null, count: number): number | null {
  if (!scores || scores.length < count) return null;
  let total = 0;
  for (let i = 0; i < count; i++) total += scores[i];
  return total;
}

function pair(home: number | null, away: number | null): Checkpoint | null {
  if (home == null || away == null) return null;
  return { home, away };
}

function teamLabel(name: unknown, abbreviation: unknown, fallback: string): string {
  const full = asNonEmptyString(name);
  const short = asNonEmptyString(abbreviation);
  if (full && full.length <= 22) return full;
  if (short) return short;
  if (full) return full.slice(0, 22);
  return fallback;
}

function formatMargin(value: number): string {
  if (nearly(value, 0.5)) return "half a point";
  return formatSpread(value);
}

function formatSpread(value: number): string {
  if (nearly(value, Math.round(value))) return String(Math.round(value));
  return (Math.round(value * 2) / 2).toFixed(1);
}

function formatScore(value: number): string {
  if (nearly(value, Math.round(value))) return String(Math.round(value));
  return String(value);
}

function clipTitle(title: string): string {
  const clean = title.replace(/\s+/g, " ").trim();
  if (clean.length <= MAX_PUSH_TITLE_LENGTH) return clean;
  return clean.slice(0, MAX_PUSH_TITLE_LENGTH).trimEnd();
}

function clipBody(body: string): string {
  const clean = body.replace(/\s+/g, " ").trim();
  if (clean.length <= MAX_PUSH_BODY_LENGTH) return clean;
  const cut = clean.slice(0, MAX_PUSH_BODY_LENGTH - 1);
  const word = cut.lastIndexOf(" ");
  const base = word > 40 ? cut.slice(0, word) : cut;
  return `${base.trimEnd()}…`;
}

function dedupe(lines: Array<string | null>): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const line of lines) {
    if (!line || seen.has(line)) continue;
    seen.add(line);
    result.push(line);
  }
  return result;
}

function capitalize(value: string): string {
  if (!value) return value;
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function nearly(left: number, right: number): boolean {
  return Math.abs(left - right) < 1e-6;
}

function finiteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) return value as Record<string, unknown>;
  return {};
}

function asString(value: unknown): string {
  if (typeof value !== "string") return "";
  return value;
}

function asNonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function firstDefined(...values: unknown[]): unknown {
  for (const value of values) {
    if (value !== undefined && value !== null) return value;
  }
  return undefined;
}
