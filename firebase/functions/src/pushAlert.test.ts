import { describe, expect, it } from "vitest";
import type { Message } from "firebase-admin/messaging";
import {
  MAX_PUSH_SUBTITLE_LENGTH,
  androidFallbackBody,
  buildGameFinalPush,
  buildLeadPush,
  buildNoPickPush,
  buildPushMessage,
  gameContextSubtitle,
  leagueThreadId,
  matchupFromGame,
} from "./pushAlert";

const LEAGUE = "Office Pool";
const GROUP = "group-1";
const WEEK = "2026-W6";

const ohioMichigan = {
  away: "MICH",
  home: "OSU",
  awayScore: 21,
  homeScore: 24,
  spreadLabel: "OSU -7",
};

function alertOf(message: Message): { title?: string; subtitle?: string; body?: string } {
  const alert = message.apns?.payload?.aps?.alert;
  if (!alert || typeof alert === "string") return {};
  return alert;
}

describe("game final push", () => {
  it("names the league and the final, and keeps the spread when it fits", () => {
    const push = buildGameFinalPush({
      leagueName: LEAGUE,
      groupId: GROUP,
      weekId: WEEK,
      gameId: "game-osu",
      pickMode: "ats",
      matchup: ohioMichigan,
    });

    expect(push.subtitle).toBe("Office Pool · MICH 21 @ OSU 24 · OSU -7");
    expect(push.subtitle.length).toBeLessThanOrEqual(MAX_PUSH_SUBTITLE_LENGTH);
    expect(push.payloadType).toBe("game_final");
    expect(push.data).toEqual({
      type: "game_final",
      groupId: GROUP,
      weekId: WEEK,
      gameId: "game-osu",
      deepLink: "pickems://league/group-1/week/2026-W6/game/game-osu",
    });
    expect(push.threadId).toBe(leagueThreadId(GROUP));
    expect(push.collapseId).toContain(GROUP);
    expect(push.collapseId).toContain("game-osu");
  });

  it("drops the spread for Straight Up and when the line would exceed 50 characters", () => {
    const straight = buildGameFinalPush({
      leagueName: LEAGUE,
      groupId: GROUP,
      weekId: WEEK,
      gameId: "game-osu",
      pickMode: "straightUp",
      matchup: ohioMichigan,
    });
    expect(straight.subtitle).toBe("Office Pool · MICH 21 @ OSU 24");
    expect(straight.subtitle).not.toContain("-7");

    const crowded = gameContextSubtitle(
      "The Extremely Long Saturday Office League Name",
      ohioMichigan
    );
    expect(crowded.length).toBeLessThanOrEqual(MAX_PUSH_SUBTITLE_LENGTH);
    expect(crowded).toContain("MICH 21 @ OSU 24");
    expect(crowded).not.toContain("OSU -7");
  });

  it("still identifies the game when the score or the team abbreviation is missing", () => {
    const push = buildGameFinalPush({
      leagueName: " ",
      groupId: GROUP,
      weekId: WEEK,
      gameId: "game-1",
      pickMode: "ats",
      matchup: matchupFromGame({
        awayTeamName: "Michigan",
        homeTeamAbbreviation: "OSU",
        spread: 3.5,
        spreadTeamId: "home",
        homeTeamId: "home",
        awayTeamId: "away",
      }),
    });
    expect(push.subtitle).toBe("League · MICH @ OSU · OSU -3.5");
    expect(push.data.gameId).toBe("game-1");
  });

  it("puts the subtitle on APNs and appends the matchup for Android", () => {
    const push = buildGameFinalPush({
      leagueName: LEAGUE,
      groupId: GROUP,
      weekId: WEEK,
      gameId: "game-osu",
      pickMode: "ats",
      matchup: ohioMichigan,
    });
    const message = buildPushMessage({
      token: "tok",
      title: "You covered",
      body: "OSU got it done. MICH 21, OSU 24. Act like you've been here.",
      data: { ...push.data, result: "covered" },
      presentation: push,
    });

    const alert = alertOf(message);
    expect(alert.title).toBe("You covered");
    expect(alert.subtitle).toBe(push.subtitle);
    expect(alert.body).toBe("OSU got it done. MICH 21, OSU 24. Act like you've been here.");
    expect(message.notification?.body).toBe(alert.body);
    expect(message.apns?.payload?.aps?.threadId).toBe("league-group-1");
    expect(message.apns?.headers?.["apns-collapse-id"]).toBe(push.collapseId);
    expect(message.android?.collapseKey).toBe("league-group-1");
    expect(message.android?.notification?.body).toBe(
      androidFallbackBody(
        "OSU got it done. MICH 21, OSU 24. Act like you've been here.",
        push.subtitle
      )
    );
    expect(message.android?.notification?.body).toContain("MICH 21 @ OSU 24");
    expect(message.data).toMatchObject({
      type: "game_final",
      groupId: GROUP,
      weekId: WEEK,
      gameId: "game-osu",
    });
  });
});

describe("no-pick push", () => {
  it("uses the game subtitle and game deep link for a single miss", () => {
    const push = buildNoPickPush({
      leagueName: LEAGUE,
      groupId: GROUP,
      weekId: WEEK,
      pickMode: "ats",
      games: [{ id: "game-osu", ...ohioMichigan }],
    });
    expect(push.payloadType).toBe("no_pick");
    expect(push.subtitle).toBe("Office Pool · MICH 21 @ OSU 24 · OSU -7");
    expect(push.data).toEqual({
      type: "no_pick",
      groupId: GROUP,
      weekId: WEEK,
      gameId: "game-osu",
      deepLink: "pickems://league/group-1/week/2026-W6/game/game-osu",
    });
    expect(push.data.gameId).toBe("game-osu");
  });

  it("uses the league and game count, and omits gameId, for a combined miss", () => {
    const push = buildNoPickPush({
      leagueName: LEAGUE,
      groupId: GROUP,
      weekId: WEEK,
      pickMode: "ats",
      games: [
        { id: "g1", ...ohioMichigan },
        { id: "g2", away: "ALA", home: "UGA", awayScore: 17, homeScore: 24, spreadLabel: "UGA -3" },
      ],
    });
    expect(push.subtitle).toBe("Office Pool · 2 games");
    expect(push.subtitle.length).toBeLessThanOrEqual(MAX_PUSH_SUBTITLE_LENGTH);
    expect(push.data).toEqual({
      type: "no_pick",
      groupId: GROUP,
      weekId: WEEK,
      deepLink: "pickems://league/group-1/week/2026-W6/pickems",
    });
    expect(push.data.gameId).toBeUndefined();
    expect(push.threadId).toBe("league-group-1");

    const message = buildPushMessage({
      token: "tok",
      title: "No pick",
      body: "No pick on 2 games. That's 2 losses.",
      data: push.data,
      presentation: push,
    });
    expect(alertOf(message).subtitle).toBe("Office Pool · 2 games");
    expect(alertOf(message).body).toBe("No pick on 2 games. That's 2 losses.");
    expect(message.android?.notification?.body).toContain("Office Pool · 2 games");
  });
});

describe("lead push", () => {
  it("uses the league and week, with no game id", () => {
    const push = buildLeadPush({
      leagueName: LEAGUE,
      groupId: GROUP,
      weekId: WEEK,
      weekNumber: 6,
    });
    expect(push.payloadType).toBe("lead");
    expect(push.subtitle).toBe("Office Pool · Week 6");
    expect(push.subtitle.length).toBeLessThanOrEqual(MAX_PUSH_SUBTITLE_LENGTH);
    expect(push.data).toEqual({
      type: "lead",
      groupId: GROUP,
      weekId: WEEK,
      deepLink: "pickems://league/group-1/week/2026-W6/leaderboard",
    });
    expect(push.data.gameId).toBeUndefined();
    expect(push.threadId).toBe(leagueThreadId(GROUP));

    const message = buildPushMessage({
      token: "tok",
      title: "You took the lead",
      body: "You're #1 on the live board.",
      data: push.data,
      presentation: push,
    });
    const alert = alertOf(message);
    expect(alert.title).toBe("You took the lead");
    expect(alert.subtitle).toBe("Office Pool · Week 6");
    expect(alert.body).toBe("You're #1 on the live board.");
    expect(message.apns?.payload?.aps?.threadId).toBe("league-group-1");
    expect(message.android?.notification?.body).toBe(
      "You're #1 on the live board. — Office Pool · Week 6"
    );
  });
});

describe("buildPushMessage", () => {
  it("leaves title and body alone when a push has no context line", () => {
    const message = buildPushMessage({
      token: "tok",
      title: "Pickems are locked",
      body: "Week 6 is locked. Good luck.",
      data: { type: "deadline_locked", groupId: GROUP, weekId: WEEK },
    });
    expect(message.notification).toEqual({
      title: "Pickems are locked",
      body: "Week 6 is locked. Good luck.",
    });
    expect(message.apns?.payload?.aps?.alert).toBeUndefined();
    expect(message.android).toBeUndefined();
    expect(message.apns?.headers?.["apns-push-type"]).toBe("alert");
  });
});
