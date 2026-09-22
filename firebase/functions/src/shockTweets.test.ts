import { describe, expect, it } from "vitest";
import {
  SHOCK_REASON,
  SHOCK_TWEET_CONFIG,
  buildDraftTweet,
  collectPickedTeamIds,
  evaluateShockTweets,
  isShockTweetWindow,
  parseLeagueGameSample,
  runShockTweetDetection,
  type LeagueGameSample,
  type ShockTweetDraft,
  type ShockTweetStore,
} from "./shockTweets";

const NOW = Date.parse("2026-09-26T23:00:00.000Z");
const SETTLED = NOW - SHOCK_TWEET_CONFIG.settleDelayMs;

function sample(overrides: Partial<LeagueGameSample> = {}): LeagueGameSample {
  return {
    gameId: "401",
    espnEventId: "401",
    homeTeamId: "alabama",
    awayTeamId: "kansas",
    homeTeamName: "Alabama",
    awayTeamName: "Kansas",
    homeTeamAbbreviation: "ALA",
    awayTeamAbbreviation: "KU",
    spread: 7,
    spreadTeamId: "alabama",
    status: "final",
    homeScore: 24,
    awayScore: 31,
    pickMode: "ats",
    pickedTeamIds: [...Array(67).fill("alabama"), ...Array(19).fill("kansas")],
    finalizedAtMs: SETTLED,
    ...overrides,
  };
}

function drafts(samples: LeagueGameSample[], nowMs = NOW): ShockTweetDraft[] {
  return evaluateShockTweets(samples, nowMs).drafts;
}

type StoredTweet = Omit<ShockTweetDraft, "status"> & { status: string };

function memoryStore(seed?: StoredTweet[]): ShockTweetStore & { docs: Map<string, StoredTweet> } {
  const docs = new Map<string, StoredTweet>();
  for (const doc of seed ?? []) docs.set(doc.id, doc);
  return {
    docs,
    async get(id) {
      const doc = docs.get(id);
      return doc ? { status: doc.status } : null;
    },
    async create(draft) {
      if (docs.has(draft.id)) return "exists";
      docs.set(draft.id, draft);
      return "created";
    },
  };
}

describe("shock tweet heuristics", () => {
  it("drafts a dog cover when 22% of an ATS slate took the dog", () => {
    const [draft] = drafts([sample()]);
    expect(draft.shockReason).toBe(SHOCK_REASON.dogCoverLowPct);
    expect(draft.status).toBe("pending");
    expect(draft.mode).toBe("ats");
    expect(draft.pickCount).toBe(86);
    expect(draft.awayPickCount).toBe(19);
    expect(draft.awayPickPct).toBe(22);
    expect(draft.homePickPct).toBe(78);
    expect(draft.coveredTeamId).toBe("kansas");
    expect(draft.winnerSide).toBe("away");
    expect(draft.id).toBe("401_ats");
    expect(draft.draftTweet).toBe(
      "FINAL: Kansas 31, Alabama 24. Only 22% of Pickems picks (19/86) took the dog — and they covered."
    );
    expect(draft.draftTweet.length).toBeLessThanOrEqual(280);
    expect(draft.draftTweet).not.toContain("http");
  });

  it("uses the straight-up dog win wording and does not mix it into the ATS percent", () => {
    const [draft] = drafts([
      sample({
        pickMode: "straightUp",
        pickedTeamIds: [...Array(67).fill("alabama"), ...Array(19).fill("kansas")],
      }),
    ]);
    expect(draft.shockReason).toBe(SHOCK_REASON.dogWinLowPct);
    expect(draft.id).toBe("401_straightUp");
    expect(draft.draftTweet).toBe(
      "FINAL: Kansas 31, Alabama 24. Only 22% of Pickems picks (19/86) took the dog — and they won."
    );
  });

  it("keeps ATS and straight up as separate documents", () => {
    const result = drafts([
      sample({ gameId: "ats-league", pickedTeamIds: [...Array(4).fill("alabama"), ...Array(2).fill("kansas")] }),
      sample({
        gameId: "su-league",
        pickMode: "straightUp",
        pickedTeamIds: [...Array(4).fill("alabama"), ...Array(2).fill("kansas")],
      }),
    ]);
    expect(result.map((draft) => draft.mode).sort()).toEqual(["ats", "straightUp"]);
    expect(result.every((draft) => draft.status === "skipped" && draft.pickCount === 6)).toBe(true);
  });

  it("sums the same ESPN event across leagues before applying min N", () => {
    const result = drafts([
      sample({
        gameId: "league-a",
        pickedTeamIds: [...Array(8).fill("alabama"), ...Array(2).fill("kansas")],
      }),
      sample({
        gameId: "league-b",
        pickedTeamIds: [...Array(8).fill("alabama"), ...Array(2).fill("kansas")],
      }),
    ]);
    expect(result).toHaveLength(1);
    expect(result[0].status).toBe("pending");
    expect(result[0].pickCount).toBe(20);
    expect(result[0].awayPickCount).toBe(4);
    expect(result[0].awayPickPct).toBe(20);
    expect(result[0].shockReason).toBe(SHOCK_REASON.dogCoverLowPct);
    expect(result[0].draftTweet).toContain("Only 20% of Pickems picks (4/20)");
  });

  it("flags a favorite push when 70% laid the points and nobody covered", () => {
    const [draft] = drafts([
      sample({
        homeScore: 28,
        awayScore: 21,
        pickedTeamIds: [...Array(7).fill("alabama"), ...Array(3).fill("kansas")],
      }),
    ]);
    expect(draft.shockReason).toBe(SHOCK_REASON.favoriteFailHighPct);
    expect(draft.status).toBe("pending");
    expect(draft.coveredTeamId).toBeNull();
    expect(draft.winnerSide).toBe("push");
    expect(draft.homePickPct).toBe(70);
    expect(draft.draftTweet).toBe(
      "FINAL: Alabama 28, Kansas 21. 70% of Pickems picks (7/10) took Alabama — and they didn't cover."
    );
  });

  it("counts a backdoor cover and ignores a straight-up tie", () => {
    const [backdoor] = drafts([
      sample({
        homeScore: 27,
        awayScore: 21,
        pickedTeamIds: [...Array(8).fill("alabama"), ...Array(2).fill("kansas")],
      }),
    ]);
    expect(backdoor.shockReason).toBe(SHOCK_REASON.dogCoverLowPct);
    expect(backdoor.coveredTeamId).toBe("kansas");
    expect(backdoor.winnerSide).toBe("away");
    expect(backdoor.draftTweet.startsWith("FINAL: Alabama 27, Kansas 21.")).toBe(true);

    expect(
      drafts([
        sample({
          pickMode: "straightUp",
          homeScore: 21,
          awayScore: 21,
          pickedTeamIds: [...Array(8).fill("alabama"), ...Array(2).fill("kansas")],
        }),
      ])
    ).toEqual([]);
  });

  it("does not shock a 69% favorite or a 36% dog", () => {
    expect(
      drafts([
        sample({
          homeScore: 28,
          awayScore: 21,
          pickedTeamIds: [...Array(69).fill("alabama"), ...Array(31).fill("kansas")],
        }),
      ])
    ).toEqual([]);
    expect(
      drafts([
        sample({
          pickedTeamIds: [...Array(64).fill("alabama"), ...Array(36).fill("kansas")],
        }),
      ])
    ).toEqual([]);
  });

  it("treats a 35% dog share as a shock and ignores a pick'em line", () => {
    const [exact] = drafts([
      sample({
        pickedTeamIds: [...Array(13).fill("alabama"), ...Array(7).fill("kansas")],
      }),
    ]);
    expect(exact.shockReason).toBe(SHOCK_REASON.dogCoverLowPct);
    expect(exact.awayPickPct).toBe(35);
    expect(exact.draftTweet).toContain("(7/20)");

    expect(drafts([sample({ spread: 0, pickedTeamIds: Array(20).fill("kansas") })])).toEqual([]);
  });
});

describe("min sample and timing", () => {
  it("writes skipped instead of pending when the shock is below min N", () => {
    const [draft] = drafts([
      sample({
        pickedTeamIds: [...Array(7).fill("alabama"), ...Array(2).fill("kansas")],
      }),
    ]);
    expect(draft.status).toBe("skipped");
    expect(draft.status).not.toBe("pending");
    expect(draft.skipReason).toBe("min_sample");
    expect(draft.shockReason).toBe(SHOCK_REASON.dogCoverLowPct);
    expect(draft.pickCount).toBe(9);
    expect(draft.draftTweet).toContain("(2/9)");
  });

  it("waits out the settle delay and drops finals outside the lookback", () => {
    const tooFresh = drafts([sample({ finalizedAtMs: NOW - SHOCK_TWEET_CONFIG.settleDelayMs + 1 })]);
    expect(tooFresh).toEqual([]);
    expect(
      evaluateShockTweets(
        [sample({ finalizedAtMs: NOW - SHOCK_TWEET_CONFIG.settleDelayMs + 1 })],
        NOW
      ).deferred
    ).toBe(1);

    const ready = drafts([sample({ finalizedAtMs: NOW - SHOCK_TWEET_CONFIG.settleDelayMs })]);
    expect(ready).toHaveLength(1);

    const stale = drafts([sample({ finalizedAtMs: NOW - SHOCK_TWEET_CONFIG.lookbackMs - 1 })]);
    expect(stale).toEqual([]);
    expect(drafts([sample({ status: "inProgress" })])).toEqual([]);
    expect(drafts([sample({ awayScore: null })])).toEqual([]);
    expect(evaluateShockTweets([sample({ finalizedAtMs: null })], NOW).deferred).toBe(1);
  });

  it("holds the tweet when leagues disagree on who covered", () => {
    const evaluation = evaluateShockTweets(
      [
        sample({ gameId: "a", spread: 3.5, homeScore: 24, awayScore: 21 }),
        sample({ gameId: "b", spread: 2.5, homeScore: 24, awayScore: 21 }),
      ],
      NOW
    );
    expect(evaluation.drafts).toEqual([]);
    expect(evaluation.held).toBe(1);
  });
});

describe("idempotency", () => {
  it("does not recreate a pending draft on a second run", async () => {
    const store = memoryStore();
    const samples = [sample()];
    const first = await runShockTweetDetection({ nowMs: NOW, samples, store });
    expect(first.created).toBe(1);
    expect(first.pending).toBe(1);
    const original = store.docs.get("401_ats");
    expect(original?.draftTweet).toContain("19/86");

    const second = await runShockTweetDetection({
      nowMs: NOW,
      samples: [
        sample({
          pickedTeamIds: [...Array(70).fill("alabama"), ...Array(10).fill("kansas")],
        }),
      ],
      store,
    });
    expect(second.created).toBe(0);
    expect(second.unchanged).toBe(1);
    expect(store.docs.size).toBe(1);
    expect(store.docs.get("401_ats")).toEqual(original);
  });

  it("leaves a posted doc and a skipped doc in place", async () => {
    const posted = sample();
    const [postedDraft] = drafts([posted]);
    const skippedSample = sample({
      espnEventId: "402",
      gameId: "402",
      pickedTeamIds: [...Array(7).fill("alabama"), ...Array(2).fill("kansas")],
    });
    const [skippedDraft] = drafts([skippedSample]);
    const store = memoryStore([{ ...postedDraft, status: "posted" }, skippedDraft]);

    const result = await runShockTweetDetection({
      nowMs: NOW,
      samples: [posted, skippedSample],
      store,
    });
    expect(result.created).toBe(0);
    expect(result.unchanged).toBe(2);
    expect(store.docs.get("401_ats")?.status).toBe("posted");
    expect(store.docs.get("402_ats")?.status).toBe("skipped");
    expect(store.docs.get("402_ats")?.pickCount).toBe(9);
  });
});

describe("pick collection and schedule", () => {
  it("counts roster picks only and ignores blank picks", () => {
    const picks = collectPickedTeamIds(
      [
        { userId: "member", picks: { "401": "kansas" } },
        { userId: "removed", picks: { "401": "alabama" } },
        { userId: "member-2", picks: { "401": "   " } },
        { userId: "member-3", picks: { other: "kansas" } },
      ],
      "401",
      ["member", "member-2", "member-3"]
    );
    expect(picks).toEqual(["kansas"]);
  });

  it("parses slate fields and rejects a non-numeric score", () => {
    const parsed = parseLeagueGameSample({
      gameId: "401",
      pickMode: "ats",
      pickedTeamIds: ["kansas"],
      finalizedAtMs: SETTLED,
      data: {
        espnEventId: "401",
        homeTeamId: "alabama",
        awayTeamId: "kansas",
        homeTeamName: "Alabama",
        awayTeamName: "Kansas",
        spread: 7,
        spreadTeamId: "alabama",
        status: "final",
        homeScore: 24,
        awayScore: "31",
      },
    });
    expect(parsed?.awayScore).toBeNull();
    expect(parsed?.espnEventId).toBe("401");
    expect(parseLeagueGameSample({
      gameId: "x",
      pickMode: "ats",
      pickedTeamIds: [],
      finalizedAtMs: null,
      data: { status: "final", spread: 7 },
    })).toBeNull();
  });

  it("opens Saturday afternoon through 11:40pm ET and Sunday midday", () => {
    expect(isShockTweetWindow(new Date("2026-09-26T18:40:00.000Z"))).toBe(false);
    expect(isShockTweetWindow(new Date("2026-09-26T19:00:00.000Z"))).toBe(true);
    expect(isShockTweetWindow(new Date("2026-09-27T03:40:00.000Z"))).toBe(true);
    expect(isShockTweetWindow(new Date("2026-09-27T04:00:00.000Z"))).toBe(false);
    expect(isShockTweetWindow(new Date("2026-09-27T16:20:00.000Z"))).toBe(true);
    expect(isShockTweetWindow(new Date("2026-09-27T17:00:00.000Z"))).toBe(false);
    expect(isShockTweetWindow(new Date("2026-09-22T20:00:00.000Z"))).toBe(false);
  });

  it("keeps a long matchup inside 280 characters without dropping the pick count", () => {
    const tweet = buildDraftTweet({
      homeTeamName: "A".repeat(180),
      awayTeamName: "B".repeat(180),
      homeTeamAbbreviation: "ALA",
      awayTeamAbbreviation: "KU",
      homeScore: 24,
      awayScore: 31,
      clause: "Only 22% of Pickems picks (19/86) took the dog — and they covered.",
    });
    expect(tweet.length).toBeLessThanOrEqual(280);
    expect(tweet).toContain("19/86");
    expect(tweet).toContain("KU 31, ALA 24");
  });
});
