import { describe, expect, it } from "vitest";
import {
  LEAD_ALERT_COOLDOWN_MS,
  shouldClaimLeadAlert,
  shouldNotifyGameFinal,
  tookTheLeadRecipients,
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
    picksByUser: { U: { G: "55" }, V: { G: "99" } },
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
      picksByUser: {
        bbenson: {},
        JBanda: {},
        Fannypack: {},
        Hayden: {},
      },
      nowMs: NOW,
    });
    expect(recipients).toEqual([]);
  });

  it("does not alert an all-zero tie on this week's board", () => {
    expect(
      realLead({
        current: [
          { id: "U", weeklyWins: 0 },
          { id: "V", weeklyWins: 0 },
        ],
        previous: {
          weekNumber: 6,
          entries: [
            { id: "U", weeklyWins: 0 },
            { id: "V", weeklyWins: 0 },
          ],
        },
        picksByUser: {},
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

  it("alerts the member who moved strictly alone into first off a locked pick", () => {
    expect(realLead()).toEqual(["U"]);
  });

  it("does not alert on a self-heal pass that changed no games", () => {
    expect(realLead({ changedGameIds: new Set() })).toEqual([]);
  });

  it("does not alert when the new leader did not pick the game that changed", () => {
    expect(
      realLead({
        games: [finalGame("G"), finalGame("H")],
        changedGameIds: new Set(["G"]),
        picksByUser: { U: { H: "55" }, V: { G: "99" } },
      })
    ).toEqual([]);
  });

  it("does not alert when the changed game is not locked for picking", () => {
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
        picksByUser: { U: { G: "55" } },
      })
    ).toEqual(["U"]);
  });

  it("does not alert off a future kickoff even when the week is otherwise locked", () => {
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
