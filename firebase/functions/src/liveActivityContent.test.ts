import { describe, expect, it } from "vitest";
import type { Aps } from "firebase-admin/messaging";
import {
  LIVE_ACTIVITY_CONTENT_VERSION,
  LIVE_ACTIVITY_DISMISS_SECONDS,
  LIVE_ACTIVITY_STALE_SECONDS,
  buildLiveActivityContentState,
  isStaleLiveActivityTokenError,
  liveActivityKey,
  planLiveActivityPushes,
  scoreLiveActivityBoard,
  type LiveActivityContentState,
} from "./liveActivityContent";
import type { SlateGameDoc } from "./scoring";

const NOW = 1_700_000_000_000;

function game(partial: {
  id: string;
  status: SlateGameDoc["status"];
  homeScore?: number;
  awayScore?: number;
  kickoff: number;
  spread?: number;
}): SlateGameDoc {
  return {
    id: partial.id,
    espnEventId: partial.id,
    homeTeamId: "HOME",
    awayTeamId: "AWAY",
    homeTeamAbbreviation: "HOME",
    awayTeamAbbreviation: "AWAY",
    homeTeamName: "Home",
    awayTeamName: "Away",
    spread: partial.spread ?? 7,
    spreadTeamId: "HOME",
    status: partial.status,
    homeScore: partial.homeScore,
    awayScore: partial.awayScore,
    kickoff: partial.kickoff,
  };
}

function content(picks: Record<string, string>, games: SlateGameDoc[], pickMode: "ats" | "straightUp" = "ats") {
  return buildLiveActivityContentState({
    games,
    picks,
    pickMode,
    wins: 0,
    losses: 0,
    pushes: 0,
    rank: null,
    rankTied: false,
    updatedAt: NOW / 1000,
  });
}

describe("live activity picks", () => {
  it("orders live games, then the next kickoff, then recent finals", () => {
    const state = content(
      { early: "HOME", late: "HOME", next: "HOME", later: "HOME", done: "HOME" },
      [
        game({ id: "done", status: "final", homeScore: 21, awayScore: 14, kickoff: 1_000 }),
        game({ id: "late", status: "inProgress", homeScore: 10, awayScore: 7, kickoff: 3_000 }),
        game({ id: "early", status: "inProgress", homeScore: 14, awayScore: 14, kickoff: 2_000 }),
        game({ id: "next", status: "scheduled", kickoff: 4_000 }),
        game({ id: "later", status: "scheduled", kickoff: 5_000 }),
      ]
    );
    expect(state.picks.map((pick) => pick.gameId)).toEqual(["early", "late", "next"]);
    expect(state.picks.map((pick) => pick.phase)).toEqual(["live", "live", "upcoming"]);
  });

  it("caps the payload at three picks", () => {
    const games = Array.from({ length: 12 }, (_, index) =>
      game({ id: `g${index}`, status: "inProgress", homeScore: 7, awayScore: 0, kickoff: index * 1000 })
    );
    const picks = Object.fromEntries(games.map((item) => [item.id, "HOME"]));
    expect(content(picks, games).picks.map((pick) => pick.gameId)).toEqual(["g0", "g1", "g2"]);
  });

  it("keeps someone else's pick off the activity", () => {
    const games = [
      game({ id: "mine", status: "inProgress", homeScore: 17, awayScore: 10, kickoff: 2_000 }),
      game({ id: "theirs", status: "final", homeScore: 28, awayScore: 7, kickoff: 1_000 }),
    ];
    const state = content({ mine: "HOME" }, games);
    expect(state.picks.map((pick) => pick.gameId)).toEqual(["mine"]);
    expect(JSON.stringify(state)).not.toContain("theirs");
  });

  it("grades ATS cover, trail, and a live push", () => {
    const state = content(
      { cover: "HOME", trail: "HOME", push: "HOME" },
      [
        game({ id: "cover", status: "inProgress", homeScore: 31, awayScore: 20, kickoff: 1_000 }),
        game({ id: "trail", status: "inProgress", homeScore: 24, awayScore: 20, kickoff: 2_000 }),
        game({ id: "push", status: "inProgress", homeScore: 27, awayScore: 20, kickoff: 3_000 }),
      ]
    );
    expect(state.picks.map((pick) => pick.resultLabel)).toEqual(["Covering", "Trailing", "Pushing"]);
  });

  it("grades straight up from the score", () => {
    const live = content(
      { su: "HOME", tie: "HOME" },
      [
        game({ id: "su", status: "inProgress", homeScore: 24, awayScore: 20, kickoff: 1_000 }),
        game({ id: "tie", status: "inProgress", homeScore: 17, awayScore: 17, kickoff: 2_000 }),
      ],
      "straightUp"
    );
    expect(live.picks.map((pick) => pick.resultLabel)).toEqual(["Winning", "Tied"]);
    const finals = content(
      { su: "HOME" },
      [game({ id: "su", status: "final", homeScore: 24, awayScore: 20, kickoff: 1_000 })],
      "ats"
    );
    expect(finals.picks[0].resultLabel).toBe("Lost");
  });

  it("hides rank at 0-0 and marks a shared rank", () => {
    const games = [game({ id: "g", status: "final", homeScore: 31, awayScore: 20, kickoff: 1_000 })];
    const board = scoreLiveActivityBoard({
      members: [
        { id: "a", displayName: "Ada" },
        { id: "b", displayName: "Bea" },
        { id: "c", displayName: "Cy" },
      ],
      picksByUserId: {
        a: { picks: { g: "HOME" } },
        b: { picks: { g: "HOME" } },
        c: { picks: {} },
      },
      games,
      pickMode: "ats",
    });
    expect(board.get("a")).toMatchObject({ wins: 1, losses: 0, rank: 1, rankTied: true });
    expect(board.get("b")).toMatchObject({ wins: 1, losses: 0, rank: 1, rankTied: true });
    expect(board.get("c")).toMatchObject({ wins: 0, losses: 1, rank: 3, rankTied: false });

    const empty = scoreLiveActivityBoard({
      members: [{ id: "a", displayName: "Ada" }],
      picksByUserId: { a: { picks: {} } },
      games: [game({ id: "live", status: "inProgress", homeScore: 7, awayScore: 0, kickoff: 1_000 })],
      pickMode: "ats",
    });
    expect(empty.get("a")?.rank).toBeNull();
  });

  it("counts a miss as a loss and doubles a confidence win", () => {
    const games = [
      game({ id: "hit", status: "final", homeScore: 31, awayScore: 20, kickoff: 1_000 }),
      game({ id: "skip", status: "final", homeScore: 10, awayScore: 7, kickoff: 2_000 }),
    ];
    const board = scoreLiveActivityBoard({
      members: [{ id: "a", displayName: "Ada" }],
      picksByUserId: { a: { picks: { hit: "HOME" }, confidenceGameId: "hit" } },
      games,
      pickMode: "ats",
    });
    expect(board.get("a")).toMatchObject({ wins: 2, losses: 1, rank: 1 });
  });
});

describe("live activity push plan", () => {
  const games = [
    game({ id: "osu", status: "inProgress", homeScore: 21, awayScore: 17, kickoff: 2_000 }),
    game({ id: "ala", status: "inProgress", homeScore: 14, awayScore: 10, kickoff: 1_000 }),
  ];
  const members = [
    { id: "ada", displayName: "Ada" },
    { id: "bea", displayName: "Bea" },
  ];
  const picksByUserId = {
    ada: { picks: { osu: "HOME" } },
    bea: { picks: { ala: "AWAY" } },
  };

  it("updates only the viewer who picked the changed game", () => {
    const plans = planLiveActivityPushes({
      games,
      members,
      picksByUserId,
      subscriptions: [
        { userId: "ada", fcmToken: "fcm-ada", liveActivityToken: "act-ada" },
        { userId: "bea", fcmToken: "fcm-bea", liveActivityToken: "act-bea" },
      ],
      changedGameIds: new Set(["osu"]),
      pickMode: "ats",
      dismiss: false,
      nowMs: NOW,
    });
    expect(plans.map((plan) => plan.userId)).toEqual(["ada"]);
    const state = contentState(plans[0].message);
    expect(state.picks.map((pick) => pick.gameId)).toEqual(["osu"]);
    expect(JSON.stringify(state)).not.toContain("ala");
    expect(state.picks[0].picked).toBe("HOME");
    expect(state.contentVersion).toBe(LIVE_ACTIVITY_CONTENT_VERSION);
    expect(plans[0].message.token).toBe("fcm-ada");
    expect(plans[0].message.apns?.liveActivityToken).toBe("act-ada");
    expect(plans[0].message.notification).toBeUndefined();
    expect(plans[0].message.apns?.headers?.["apns-push-type"]).toBe("liveactivity");
    const aps = plans[0].message.apns?.payload?.aps as Aps & Record<string, unknown>;
    expect(aps.event).toBe("update");
    expect(aps.timestamp).toBe(NOW / 1000);
    expect(aps["stale-date"]).toBe(NOW / 1000 + LIVE_ACTIVITY_STALE_SECONDS);
    expect(aps["content-state"]).toBe(state);
  });

  it("ends the activity for every subscribed member when the week is dismissed", () => {
    const plans = planLiveActivityPushes({
      games,
      members,
      picksByUserId,
      subscriptions: [
        { userId: "ada", fcmToken: "fcm-ada", liveActivityToken: "act-ada" },
        { userId: "bea", fcmToken: "fcm-bea", liveActivityToken: "act-bea" },
        { userId: "cy", fcmToken: "fcm-cy", liveActivityToken: "act-cy" },
        { userId: "ada", fcmToken: "", liveActivityToken: "act" },
      ],
      changedGameIds: new Set(),
      pickMode: "ats",
      dismiss: true,
      nowMs: NOW,
    });
    expect(plans.map((plan) => plan.userId).sort()).toEqual(["ada", "bea"]);
    const aps = plans[0].message.apns?.payload?.aps as Aps & Record<string, unknown>;
    expect(aps.event).toBe("end");
    expect(aps["dismissal-date"]).toBe(NOW / 1000 + LIVE_ACTIVITY_DISMISS_SECONDS);
    const ada = plans.find((plan) => plan.userId === "ada");
    const bea = plans.find((plan) => plan.userId === "bea");
    expect(contentState(ada!.message).picks.map((pick) => pick.gameId)).toEqual(["osu"]);
    expect(contentState(bea!.message).picks.map((pick) => pick.picked)).toEqual(["AWAY"]);
    expect(JSON.stringify(contentState(bea!.message))).not.toContain("osu");
  });

  it("builds the activity key the app stores", () => {
    expect(liveActivityKey("league-1", "2026-W6")).toBe("league-1|2026-W6");
  });
});

describe("isStaleLiveActivityTokenError", () => {
  it("clears an APNs activity token and leaves an FCM device error alone", () => {
    expect(isStaleLiveActivityTokenError({ message: "APNs BadDeviceToken" })).toBe(true);
    expect(isStaleLiveActivityTokenError({ message: "Unregistered" })).toBe(true);
    expect(
      isStaleLiveActivityTokenError({
        code: "messaging/registration-token-not-registered",
        message: "Unregistered",
      })
    ).toBe(false);
    expect(isStaleLiveActivityTokenError({ code: "messaging/invalid-argument", message: "bad payload" })).toBe(
      false
    );
  });
});

function contentState(message: { apns?: { payload?: { aps: Aps } } }): LiveActivityContentState {
  const aps = message.apns?.payload?.aps as Aps & { "content-state"?: LiveActivityContentState };
  if (!aps["content-state"]) throw new Error("missing content-state");
  return aps["content-state"];
}
