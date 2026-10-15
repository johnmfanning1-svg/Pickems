import { describe, expect, it } from "vitest";
import { MAX_PUSH_BODY_LENGTH, MAX_PUSH_TITLE_LENGTH } from "./pushCopy";
import { buildSelectionVetoPush, gameDeepLink } from "./pushAlert";
import {
  DEFAULT_VETO_VOTES_NEEDED,
  SELECTION_VETO_LEAGUE_TITLE,
  SELECTION_VETO_SELECTOR_TITLE,
  effectiveVetoVotesNeeded,
  eligibleVetoVoterIds,
  nominationCountAfterRemoval,
  nominationEventIdsAfterRemoval,
  planSelectionVeto,
  selectionMatchupLabel,
  selectionVetoDeliverySucceeded,
  SELECTION_VETO_SETTINGS_TRIGGER,
  SELECTION_VETO_VOTE_TRIGGER,
  selectionVetoMessages,
  indexOfPendingVetoRecord,
  selectionVetoRecordId,
  selectionVetoTitlesFit,
  selectionVetoWindowOpen,
  slateGameIdsForEvent,
  vetoSettingsMayApply,
  type SelectionVetoPlan,
} from "./selectionVeto";

const NOW = Date.parse("2026-10-10T16:00:00Z");
const KICKOFF = NOW + 60 * 60 * 1000;
const DEADLINE = NOW + 30 * 60 * 1000;
const MEMBERS = ["commish", "selector", "m2", "m3"];

function openInput(overrides: Record<string, unknown> = {}) {
  return {
    nowMs: NOW,
    vetoEnabled: true,
    configuredVotesNeeded: 2,
    memberIds: MEMBERS,
    weekStatus: "selection",
    weekSelectionMode: "member",
    groupSelectionMode: "member",
    selectionDeadlineMs: DEADLINE,
    kickoffMs: KICKOFF,
    selectorId: "selector",
    voterIds: [] as string[],
    triggerVoterId: null as string | null,
    nominationExists: true,
    vetoRecorded: false,
    vetoNotified: false,
    ...overrides,
  };
}

describe("selection veto threshold", () => {
  it("defaults to 2 and caps at one less than the league size", () => {
    expect(DEFAULT_VETO_VOTES_NEEDED).toBe(2);
    expect(effectiveVetoVotesNeeded(undefined, 8)).toBe(2);
    expect(effectiveVetoVotesNeeded(2, 4)).toBe(2);
    expect(effectiveVetoVotesNeeded(9, 4)).toBe(3);
    expect(effectiveVetoVotesNeeded(0, 6)).toBe(2);
    expect(effectiveVetoVotesNeeded(1, 2)).toBe(1);
  });

  it("cannot resolve a threshold when nobody else can vote", () => {
    expect(effectiveVetoVotesNeeded(2, 1)).toBeNull();
    expect(effectiveVetoVotesNeeded(2, 0)).toBeNull();
  });
});

describe("selection veto window", () => {
  const open = {
    nowMs: NOW,
    weekStatus: "selection",
    weekSelectionMode: "member",
    groupSelectionMode: "member",
    selectionDeadlineMs: DEADLINE,
    kickoffMs: KICKOFF,
  };

  it("is open with no deadline while the kickoff is ahead", () => {
    expect(selectionVetoWindowOpen({ ...open, selectionDeadlineMs: null })).toBe(true);
  });

  it("closes when Pickems are open, the deadline hits, or the game kicks off", () => {
    expect(selectionVetoWindowOpen({ ...open, weekStatus: "picking" })).toBe(false);
    expect(selectionVetoWindowOpen({ ...open, weekStatus: "locked" })).toBe(false);
    expect(selectionVetoWindowOpen({ ...open, nowMs: DEADLINE })).toBe(false);
    expect(selectionVetoWindowOpen({ ...open, nowMs: KICKOFF })).toBe(false);
    expect(selectionVetoWindowOpen({ ...open, kickoffMs: null })).toBe(false);
  });

  it("stays closed in commissioner mode", () => {
    expect(selectionVetoWindowOpen({ ...open, weekSelectionMode: "commissioner" })).toBe(false);
    expect(selectionVetoWindowOpen({ ...open, groupSelectionMode: "commissioner" })).toBe(false);
  });
});

describe("planSelectionVeto", () => {
  it("tallies an eligible vote and ignores the selector, outsiders, and duplicates", () => {
    const plan = planSelectionVeto(
      openInput({
        voterIds: ["m2", "selector", "outsider", "m2"],
        triggerVoterId: "m2",
      })
    );
    expect(plan).toEqual({ kind: "tally", count: 1, votesNeeded: 2 });
    expect(eligibleVetoVoterIds(["m2", "selector", "outsider", "m2"], MEMBERS, "selector")).toEqual([
      "m2",
    ]);
  });

  it("removes the selection once the clamped threshold is met", () => {
    const plan = planSelectionVeto(
      openInput({
        configuredVotesNeeded: 99,
        voterIds: ["m2", "m3", "commish"],
        triggerVoterId: "commish",
      })
    );
    expect(plan).toEqual({ kind: "apply", count: 3, votesNeeded: 3 });
  });

  it("applies at exactly the required count", () => {
    const plan = planSelectionVeto(
      openInput({ voterIds: ["m2", "m3"], triggerVoterId: "m3" })
    );
    expect(plan.kind).toBe("apply");
  });

  it("drops the selector's own vote and a vote cast while veto is off", () => {
    expect(planSelectionVeto(openInput({ voterIds: ["selector"], triggerVoterId: "selector" })).kind).toBe(
      "drop_trigger_vote"
    );
    expect(
      planSelectionVeto(openInput({ vetoEnabled: false, voterIds: ["m2"], triggerVoterId: "m2" })).kind
    ).toBe("drop_trigger_vote");
  });

  it("does not remove a selection after Selections close or kickoff", () => {
    const closed: SelectionVetoPlan = planSelectionVeto(
      openInput({ weekStatus: "picking", voterIds: ["m2", "m3"], triggerVoterId: "m3" })
    );
    expect(closed.kind).toBe("skip");
    expect(
      planSelectionVeto(openInput({ nowMs: KICKOFF, voterIds: ["m2", "m3"], triggerVoterId: "m3" })).kind
    ).toBe("skip");
    expect(
      planSelectionVeto(
        openInput({ nowMs: DEADLINE, voterIds: ["m2", "m3"], triggerVoterId: "m3" })
      ).kind
    ).toBe("skip");
  });

  it("keeps a legal vote that arrives as the window closes instead of deleting it", () => {
    expect(
      planSelectionVeto(openInput({ nowMs: DEADLINE, voterIds: ["m2"], triggerVoterId: "m2" })).kind
    ).toBe("skip");
  });

  it("still applies when an ineligible vote arrives on top of a reached threshold", () => {
    const plan = planSelectionVeto(
      openInput({ voterIds: ["m2", "m3", "selector"], triggerVoterId: "selector" })
    );
    expect(plan).toEqual({ kind: "apply", count: 2, votesNeeded: 2 });
  });

  it("does nothing for a one-person league", () => {
    expect(
      planSelectionVeto(openInput({ memberIds: ["selector"], voterIds: [], triggerVoterId: null })).kind
    ).toBe("skip");
  });

  it("notifies on retry after the selection is already gone", () => {
    expect(
      planSelectionVeto(
        openInput({ nominationExists: false, vetoRecorded: true, vetoNotified: false })
      ).kind
    ).toBe("notify_only");
    expect(
      planSelectionVeto(
        openInput({ nominationExists: false, vetoRecorded: true, vetoNotified: true })
      ).kind
    ).toBe("skip");
    expect(planSelectionVeto(openInput({ nominationExists: false })).kind).toBe("skip");
  });

  it("drops a vote on a selection with no selector", () => {
    expect(planSelectionVeto(openInput({ selectorId: "  ", triggerVoterId: "m2" })).kind).toBe(
      "drop_trigger_vote"
    );
  });
});

describe("veto settings recheck", () => {
  const base = {
    memberIds: MEMBERS,
    rules: { vetoEnabled: true, vetoVotesNeeded: 3, selectionMode: "member" },
  };

  it("rechecks when veto is turned on, the threshold drops, or the roster shrinks", () => {
    expect(vetoSettingsMayApply({ ...base, rules: { ...base.rules, vetoEnabled: false } }, base)).toBe(
      true
    );
    expect(
      vetoSettingsMayApply(base, { ...base, rules: { ...base.rules, vetoVotesNeeded: 2 } })
    ).toBe(true);
    expect(vetoSettingsMayApply(base, { ...base, memberIds: ["commish", "selector", "m2"] })).toBe(true);
  });

  it("ignores unrelated league edits and turning veto off", () => {
    expect(vetoSettingsMayApply(base, { ...base, name: "Renamed" })).toBe(false);
    expect(
      vetoSettingsMayApply(base, { ...base, rules: { ...base.rules, vetoEnabled: false } })
    ).toBe(false);
    expect(
      vetoSettingsMayApply(base, { ...base, rules: { ...base.rules, vetoVotesNeeded: 4 } })
    ).toBe(false);
  });
});

describe("selection veto record and slate cleanup", () => {
  it("keys the record by selector and game", () => {
    expect(selectionVetoRecordId("selector", "401")).toBe("selector_401");
  });

  it("a retry announces the veto that has not been sent", () => {
    expect(indexOfPendingVetoRecord([{ notified: true }, { notified: false }])).toBe(1);
    expect(indexOfPendingVetoRecord([{ notified: true }])).toBe(0);
    expect(indexOfPendingVetoRecord([])).toBe(-1);
  });

  it("frees the slot by dropping that nomination from the count and matching slate docs", () => {
    expect(nominationCountAfterRemoval(["401", "402"], "401")).toBe(1);
    expect(nominationCountAfterRemoval(["401"], "401")).toBe(0);
    const games = [
      { id: "401", espnEventId: "401" },
      { id: "other", espnEventId: "401" },
      { id: "402", espnEventId: "402" },
    ];
    expect(slateGameIdsForEvent(games, "401", ["401"]).sort()).toEqual([]);
    expect(slateGameIdsForEvent(games, "401", []).sort()).toEqual(["401", "other"]);
    expect(
      nominationEventIdsAfterRemoval(
        [
          { id: "401", espnEventId: "401" },
          { id: "401-other", espnEventId: "401" },
        ],
        "401"
      )
    ).toEqual(["401"]);
  });

  it("marks the veto announced only after every send succeeds", () => {
    expect(selectionVetoDeliverySucceeded([true, true])).toBe(true);
    expect(selectionVetoDeliverySucceeded([true, false])).toBe(false);
    expect(selectionVetoDeliverySucceeded([])).toBe(false);
    expect(SELECTION_VETO_VOTE_TRIGGER.retry).toBe(true);
    expect(SELECTION_VETO_SETTINGS_TRIGGER.retry).toBe(true);
  });
});

describe("selection veto push copy", () => {
  it("uses a distinct selector message and names the game and the league", () => {
    expect(selectionVetoTitlesFit()).toBe(true);
    expect(SELECTION_VETO_SELECTOR_TITLE.length).toBeLessThanOrEqual(MAX_PUSH_TITLE_LENGTH);
    expect(SELECTION_VETO_LEAGUE_TITLE.length).toBeLessThanOrEqual(MAX_PUSH_TITLE_LENGTH);

    const messages = selectionVetoMessages("ALA @ UGA", "Office Pool");
    expect(messages.selector.title).not.toBe(messages.league.title);
    expect(messages.selector.body).not.toBe(messages.league.body);
    expect(messages.selector.body).toContain("ALA @ UGA");
    expect(messages.selector.body).toContain("Office Pool");
    expect(messages.selector.body).toContain("slot");
    expect(messages.league.body).toContain("ALA @ UGA");
    expect(messages.league.body).toContain("Office Pool");
    expect(messages.league.body).not.toContain("slot");
    expect(messages.selector.body.length).toBeLessThanOrEqual(MAX_PUSH_BODY_LENGTH);
    expect(messages.league.body.length).toBeLessThanOrEqual(MAX_PUSH_BODY_LENGTH);
  });

  it("keeps the game and the league in the body when the names are long", () => {
    const game = selectionMatchupLabel({
      awayTeamAbbreviation: "MICH",
      homeTeamAbbreviation: "OSU",
    });
    const messages = selectionVetoMessages(game, "The Extremely Long Saturday Office League Name");
    expect(messages.selector.body).toContain("MICH @ OSU");
    expect(messages.selector.body).toContain("was vetoed in");
    expect(messages.league.body).toContain("MICH @ OSU");
    expect(messages.league.body.length).toBeLessThanOrEqual(MAX_PUSH_BODY_LENGTH);
    expect(messages.selector.body.length).toBeLessThanOrEqual(MAX_PUSH_BODY_LENGTH);
  });

  it("deep-links every alert to that game in that league and week", () => {
    const push = buildSelectionVetoPush({
      leagueName: "Office Pool",
      groupId: "group 1",
      weekId: "2026-W6",
      gameId: "401",
      away: "ALA",
      home: "UGA",
    });
    expect(push.payloadType).toBe("selection_veto");
    expect(push.subtitle).toContain("Office Pool");
    expect(push.subtitle).toContain("ALA @ UGA");
    expect(push.data).toEqual({
      type: "selection_veto",
      groupId: "group 1",
      weekId: "2026-W6",
      gameId: "401",
      deepLink: gameDeepLink("group 1", "2026-W6", "401"),
    });
    expect(push.data.deepLink).toBe("pickems://league/group%201/week/2026-W6/game/401");
    expect(push.collapseId).toContain("veto");
    expect(push.threadId).toContain("group 1");
  });
});
