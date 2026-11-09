import { describe, expect, it } from "vitest";
import {
  LEAD_ALERT_COOLDOWN_MS,
  shouldClaimLeadAlert,
  shouldNotifyGameFinal,
  tookTheLeadRecipients,
  userIdsWithPicks,
  type LeadAlertEntry,
  type LeadAlertGame,
} from "./leadAlert";

const NOW = Date.parse("2026-10-08T12:36:00.000Z");
const KICKOFF = Date.parse("2026-10-07T23:00:00.000Z");

function rollingWeek(status: string = "picking") {
  return {
    status,
    pickLockMode: "rolling",
    gameKickoffs: { G: KICKOFF },
  };
}

function finalGame(id = "G", kickoff: unknown = KICKOFF): LeadAlertGame {
  return { id, status: "final", kickoff };
}

/** Real lead change: U 2→4, V stays at 3, U picked the changed final. */
function realLead(overrides: Partial<Parameters<typeof tookTheLeadRecipients>[0]> = {}) {
  const current: LeadAlertEntry[] = [
    { id: "U", weeklyWins: 4 },
    { id: "V", weeklyWins: 3 },
  ];
  return tookTheLeadRecipients({
    weekNumber: 6,
    week: rollingWeek(),
    current,
    previous: {
      weekNumber: 6,
      entries: [
        { id: "U", weeklyWins: 2 },
        { id: "V", weeklyWins: 3 },
      ],
    },
    games: [finalGame()],
    changedGameIds: new Set(["G"]),
    nowMs: NOW,
    ...overrides,
  });
}

describe("tookTheLeadRecipients", () => {
  it("does not alert the Core 4 OG W6 all-zero board against last week's final ranks", () => {
    // Thu Oct 8 2026, 8:36 AM ET. Game 401871051 was already played when it
    // landed on the slate. Nobody picked it; every member was 0–1 and rank 1.
    // standings/current was still Week 5.
    const recipients = tookTheLeadRecipients({
      weekNumber: 6,
      week: {
        status: "picking",
        pickLockMode: "rolling",
        gameKickoffs: { "401871051": new Date("2026-10-07T23:00:00.000Z") },
      },
      current: [
        { id: "bbenson", weeklyWins: 0 },
        { id: "JBanda", weeklyWins: 0 },
        { id: "Fannypack", weeklyWins: 0 },
        { id: "Hayden", weeklyWins: 0 },
      ],
      previous: {
        weekNumber: 5,
        entries: [
          { id: "bbenson", weeklyWins: 8 },
          { id: "JBanda", weeklyWins: 6 },
          { id: "Fannypack", weeklyWins: 5 },
          { id: "Hayden", weeklyWins: 5 },
        ],
      },
      games: [
        {
          id: "401871051",
          status: "final",
          kickoff: new Date("2026-10-07T23:00:00.000Z"),
        },
      ],
      changedGameIds: new Set(["401871051"]),
      nowMs: NOW,
    });
    expect(recipients).toEqual([]);
  });

  it("does not alert this morning's all-zero tie, even on this week's board", () => {
    // Core 4 OG W6 ended 0–0 for everyone. Compared with this week, after a
    // locked final moved the board, so the cross-week guard is not the block.
    // A tie at 0 is not a lead.
    expect(
      realLead({
        current: [
          { id: "bbenson", weeklyWins: 0 },
          { id: "JBanda", weeklyWins: 0 },
          { id: "Fannypack", weeklyWins: 0 },
          { id: "Hayden", weeklyWins: 0 },
        ],
        previous: {
          weekNumber: 6,
          entries: [
            { id: "bbenson", weeklyWins: 1 },
            { id: "JBanda", weeklyWins: 0 },
            { id: "Fannypack", weeklyWins: 0 },
            { id: "Hayden", weeklyWins: 0 },
          ],
        },
      })
    ).toEqual([]);
  });

  it("does not treat a tie at the top as the lead", () => {
    expect(
      realLead({
        current: [
          { id: "U", weeklyWins: 3 },
          { id: "V", weeklyWins: 3 },
        ],
        previous: {
          weekNumber: 6,
          entries: [
            { id: "U", weeklyWins: 2 },
            { id: "V", weeklyWins: 3 },
          ],
        },
      })
    ).toEqual([]);
  });

  it("alerts the member who is now strictly alone in first after a locked final", () => {
    expect(realLead()).toEqual(["U"]);
  });

  it("does not alert when the final game's kickoff is still in the future", () => {
    const future = NOW + 60_000;
    expect(
      realLead({
        week: {
          status: "picking",
          pickLockMode: "rolling",
          gameKickoffs: { G: future },
        },
        games: [finalGame("G", future)],
      })
    ).toEqual([]);
  });

  it("alerts when a rival drops and the leader's own score stays the same", () => {
    const current = [
      { id: "U", weeklyWins: 3 },
      { id: "V", weeklyWins: 2 },
    ];
    expect(
      realLead({
        current,
        previous: {
          weekNumber: 6,
          entries: [
            { id: "U", weeklyWins: 3 },
            { id: "V", weeklyWins: 4 },
          ],
        },
      })
    ).toEqual(["U"]);
    expect(
      realLead({
        current,
        previous: {
          weekNumber: 6,
          entries: [
            { id: "U", weeklyWins: 3 },
            { id: "V", weeklyWins: 3 },
          ],
        },
      })
    ).toEqual(["U"]);
  });

  it("does not alert on a self-heal pass that changed no games", () => {
    expect(realLead({ changedGameIds: new Set() })).toEqual([]);
  });

  it("does not alert when an unlocked game goes final", () => {
    expect(
      realLead({
        week: {
          status: "picking",
          pickLockMode: "firstKickoff",
          pickDeadline: NOW + 60 * 60 * 1000,
          gameKickoffs: { G: KICKOFF },
        },
      })
    ).toEqual([]);
  });

  it("does not alert someone who was already the sole leader", () => {
    expect(
      realLead({
        current: [
          { id: "U", weeklyWins: 4 },
          { id: "V", weeklyWins: 2 },
        ],
        previous: {
          weekNumber: 6,
          entries: [
            { id: "U", weeklyWins: 3 },
            { id: "V", weeklyWins: 2 },
          ],
        },
      })
    ).toEqual([]);
  });

  it("does not alert when there is no previous standings doc", () => {
    expect(realLead({ previous: undefined })).toEqual([]);
  });

  it("alerts a newly added member who is now strictly ahead", () => {
    expect(
      realLead({
        current: [
          { id: "U", weeklyWins: 2 },
          { id: "V", weeklyWins: 1 },
        ],
        previous: {
          weekNumber: 6,
          entries: [{ id: "V", weeklyWins: 1 }],
        },
      })
    ).toEqual(["U"]);
  });

  it("does not alert while the week is in selection or already scored", () => {
    expect(realLead({ week: rollingWeek("selection") })).toEqual([]);
    expect(realLead({ week: rollingWeek("scored") })).toEqual([]);
  });

  it("alerts the only member once they have points and were not already ahead", () => {
    expect(
      realLead({
        current: [{ id: "U", weeklyWins: 1 }],
        previous: { weekNumber: 6, entries: [{ id: "U", weeklyWins: 0 }] },
      })
    ).toEqual(["U"]);
  });

  it("does not alert when a future game goes final", () => {
    const future = NOW + 60 * 60 * 1000;
    expect(
      realLead({
        week: {
          status: "locked",
          pickLockMode: "rolling",
          remainingLockAt: NOW - 1000,
          gameKickoffs: { G: future },
        },
        games: [finalGame("G", future)],
      })
    ).toEqual([]);
  });

  it("does not alert a rolling-lock Thursday 1–0 when most of the roster has no pick doc", () => {
    // First Thursday final. One member picked it correctly. Everyone else
    // missed the lock and is an automatic 0–1. That is not a lead yet.
    const roster = ["U", "V", "W", "X"].map((id, index) => ({
      id,
      weeklyWins: index === 0 ? 1 : 0,
    }));
    const zeros = roster.map((entry) => ({ id: entry.id, weeklyWins: 0 }));
    expect(
      realLead({
        current: roster,
        previous: { weekNumber: 6, entries: zeros },
        pickedUserIds: new Set(["U"]),
      })
    ).toEqual([]);
  });

  it("alerts a rolling-lock Thursday sole leader once at least half the roster has a pick doc", () => {
    // Same 1–0 board, but half the league has actually picked. One final is enough.
    const roster = ["U", "V", "W", "X"].map((id, index) => ({
      id,
      weeklyWins: index === 0 ? 1 : 0,
    }));
    const zeros = roster.map((entry) => ({ id: entry.id, weeklyWins: 0 }));
    expect(
      realLead({
        current: roster,
        previous: { weekNumber: 6, entries: zeros },
        pickedUserIds: new Set(["U", "V"]),
      })
    ).toEqual(["U"]);

    // 2 of 5 is still most of the roster with no pick doc.
    const five = ["U", "V", "W", "X", "Y"].map((id, index) => ({
      id,
      weeklyWins: index === 0 ? 1 : 0,
    }));
    expect(
      realLead({
        current: five,
        previous: {
          weekNumber: 6,
          entries: five.map((entry) => ({ id: entry.id, weeklyWins: 0 })),
        },
        pickedUserIds: new Set(["U", "V"]),
      })
    ).toEqual([]);
  });

  it("alerts a mid-weekend sole leader when most of the roster has a pick doc", () => {
    const saturday = Date.parse("2026-10-10T23:40:00.000Z");
    const thursday = Date.parse("2026-10-09T00:20:00.000Z");
    const early = Date.parse("2026-10-10T16:00:00.000Z");
    const late = Date.parse("2026-10-10T20:15:00.000Z");
    expect(
      realLead({
        week: {
          status: "picking",
          pickLockMode: "rolling",
          gameKickoffs: { THU: thursday, SAT1: early, SAT2: late },
        },
        current: [
          { id: "U", weeklyWins: 3 },
          { id: "V", weeklyWins: 2 },
          { id: "W", weeklyWins: 1 },
          { id: "X", weeklyWins: 0 },
        ],
        previous: {
          weekNumber: 6,
          entries: [
            { id: "U", weeklyWins: 2 },
            { id: "V", weeklyWins: 2 },
            { id: "W", weeklyWins: 1 },
            { id: "X", weeklyWins: 0 },
          ],
        },
        games: [finalGame("THU", thursday), finalGame("SAT1", early), finalGame("SAT2", late)],
        changedGameIds: new Set(["SAT2"]),
        pickedUserIds: new Set(["U", "V", "W"]),
        nowMs: saturday,
      })
    ).toEqual(["U"]);
  });

  it("does not alert a rolling-lock sole leader when most have no pick doc, even after several finals", () => {
    const saturday = Date.parse("2026-10-10T23:40:00.000Z");
    const thursday = Date.parse("2026-10-09T00:20:00.000Z");
    const early = Date.parse("2026-10-10T16:00:00.000Z");
    const late = Date.parse("2026-10-10T20:15:00.000Z");
    expect(
      realLead({
        week: {
          status: "picking",
          pickLockMode: "rolling",
          gameKickoffs: { THU: thursday, SAT1: early, SAT2: late },
        },
        current: [
          { id: "U", weeklyWins: 3 },
          { id: "V", weeklyWins: 0 },
          { id: "W", weeklyWins: 0 },
          { id: "X", weeklyWins: 0 },
        ],
        previous: {
          weekNumber: 6,
          entries: [
            { id: "U", weeklyWins: 2 },
            { id: "V", weeklyWins: 0 },
            { id: "W", weeklyWins: 0 },
            { id: "X", weeklyWins: 0 },
          ],
        },
        games: [finalGame("THU", thursday), finalGame("SAT1", early), finalGame("SAT2", late)],
        changedGameIds: new Set(["SAT2"]),
        pickedUserIds: new Set(["U"]),
        nowMs: saturday,
      })
    ).toEqual([]);
  });

  it("still alerts a deadline-lock sole leader when most of the roster has no pick doc", () => {
    expect(
      realLead({
        week: {
          status: "locked",
          pickLockMode: "firstKickoff",
          pickDeadline: KICKOFF,
          gameKickoffs: { G: KICKOFF },
        },
        current: [
          { id: "U", weeklyWins: 1 },
          { id: "V", weeklyWins: 0 },
          { id: "W", weeklyWins: 0 },
          { id: "X", weeklyWins: 0 },
        ],
        previous: {
          weekNumber: 6,
          entries: [
            { id: "U", weeklyWins: 0 },
            { id: "V", weeklyWins: 0 },
            { id: "W", weeklyWins: 0 },
            { id: "X", weeklyWins: 0 },
          ],
        },
        pickedUserIds: new Set(["U"]),
      })
    ).toEqual(["U"]);
  });
});

describe("userIdsWithPicks", () => {
  it("counts a doc with a team and ignores blanks", () => {
    expect(
      userIdsWithPicks([
        { userId: "U", picks: { G: "HOME" } },
        { userId: "V", picks: { G: "  " } },
        { userId: "W", picks: {} },
        { userId: "X" },
        { userId: "", picks: { G: "HOME" } },
        { picks: { G: "HOME" } },
      ])
    ).toEqual(new Set(["U"]));
  });
});

describe("shouldClaimLeadAlert", () => {
  const now = 1_700_000_000_000;

  it("claims when no dedupe doc exists", () => {
    expect(shouldClaimLeadAlert(undefined, 4, now)).toBe(true);
    expect(shouldClaimLeadAlert(null, 4, now)).toBe(true);
  });

  it("skips when this score was already sent", () => {
    expect(
      shouldClaimLeadAlert(
        { lastWins: 4, lastSentAt: { toMillis: () => now - 2 * 60 * 60 * 1000 }, count: 1 },
        4,
        now
      )
    ).toBe(false);
  });

  it("skips inside the 30 minute cooldown even if the score increased", () => {
    expect(
      shouldClaimLeadAlert(
        { lastWins: 3, lastSentAt: { toMillis: () => now - 10 * 60 * 1000 }, count: 1 },
        4,
        now
      )
    ).toBe(false);
  });

  it("skips once the weekly cap is hit", () => {
    expect(
      shouldClaimLeadAlert(
        {
          lastWins: 2,
          lastSentAt: { toMillis: () => now - 2 * LEAD_ALERT_COOLDOWN_MS },
          count: 3,
        },
        4,
        now
      )
    ).toBe(false);
  });

  it("claims when the score increased, the cooldown has passed, and the cap is open", () => {
    expect(
      shouldClaimLeadAlert(
        { lastWins: 3, lastSentAt: { toMillis: () => now - 2 * 60 * 60 * 1000 }, count: 1 },
        4,
        now
      )
    ).toBe(true);
  });
});

describe("shouldNotifyGameFinal", () => {
  it("sends on the first transition into final", () => {
    expect(shouldNotifyGameFinal({ prevStatus: "scheduled", nextStatus: "final" })).toBe(true);
    expect(shouldNotifyGameFinal({ prevStatus: "inProgress", nextStatus: "final" })).toBe(true);
  });

  it("does not send when the game was already final", () => {
    expect(shouldNotifyGameFinal({ prevStatus: "final", nextStatus: "final" })).toBe(false);
  });

  // KNOWN ISSUE (October audit): the scorer stamps status final on the first
  // pass. If that pass skips the push because kickoff has not passed, the next
  // pass sees prevStatus final and never sends, even though finalNotifiedAt was
  // never set. Intended: a final with no finalNotifiedAt is retried.
  it.fails("retries a final push that an earlier pass skipped", () => {
    expect(
      shouldNotifyGameFinal({ prevStatus: "final", nextStatus: "final", finalNotifiedAt: undefined })
    ).toBe(true);
  });

  it("does not send when a prior pass already stamped finalNotifiedAt", () => {
    expect(
      shouldNotifyGameFinal({
        prevStatus: "scheduled",
        nextStatus: "final",
        finalNotifiedAt: { toMillis: () => NOW },
      })
    ).toBe(false);
  });
});
