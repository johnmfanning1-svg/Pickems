import { describe, it, expect } from "vitest";
import { HttpsError } from "firebase-functions/v2/https";
import {
  planLeaguePickModeSwitch,
  weekOrder,
  type PickModeGroupData,
  type PickModeWeek,
} from "./leaguePickMode";
import { resolveWeekPickMode } from "./scoring";

const atsLeague: PickModeGroupData = { commissionerId: "comm", rules: { pickMode: "ats" } };
const suLeague: PickModeGroupData = { commissionerId: "comm", rules: { pickMode: "straightUp" } };

function week(id: string, weekNumber: number, status: string, pickMode?: string): PickModeWeek {
  return {
    id,
    data: { seasonYear: 2026, weekNumber, status, ...(pickMode ? { pickMode } : {}) },
  };
}

/** Season so far: W1–W4 scored (W3 was a one-off Straight Up week), W5 current, W6 minted ahead. */
function season(currentStatus: string, currentPickMode?: string): PickModeWeek[] {
  return [
    week("2026-W1", 1, "scored"),
    week("2026-W2", 2, "scored"),
    week("2026-W3", 3, "scored", "straightUp"),
    week("2026-W4", 4, "scored"),
    week("2026-W5", 5, currentStatus, currentPickMode),
    week("2026-W6", 6, "selection", "straightUp"),
  ];
}

function plan(overrides: Partial<Parameters<typeof planLeaguePickModeSwitch>[0]> = {}) {
  return planLeaguePickModeSwitch({
    callerUid: "comm",
    callerIsAdmin: false,
    group: atsLeague,
    newMode: "straightUp",
    applyToCurrentWeek: true,
    currentWeekId: "2026-W5",
    weeks: season("selection"),
    ...overrides,
  });
}

function writesById(result: ReturnType<typeof plan>) {
  return Object.fromEntries(result.weekWrites.map((w) => [w.id, w.pickMode]));
}

function codeOf(fn: () => unknown): string | undefined {
  try {
    fn();
  } catch (error) {
    return error instanceof HttpsError ? error.code : "not-https-error";
  }
  return undefined;
}

describe("planLeaguePickModeSwitch: access", () => {
  it("rejects a missing league and a non-commissioner", () => {
    expect(codeOf(() => plan({ group: undefined }))).toBe("not-found");
    expect(codeOf(() => plan({ callerUid: "member" }))).toBe("permission-denied");
  });

  it("lets an admin change any league", () => {
    expect(codeOf(() => plan({ callerUid: "support", callerIsAdmin: true }))).toBeUndefined();
  });
});

describe("planLeaguePickModeSwitch: apply to this week and going forward", () => {
  it("switches the current week, pins past weeks, and clears future overrides", () => {
    const result = plan();
    expect(result.previousMode).toBe("ats");
    expect(result.rulesNeedUpdate).toBe(true);
    expect(result.currentWeekApplied).toBe(true);
    expect(writesById(result)).toEqual({
      "2026-W1": "ats",
      "2026-W2": "ats",
      "2026-W4": "ats",
      "2026-W5": "straightUp",
      "2026-W6": null,
    });
  });

  it("never rewrites a stored mode on a scored week", () => {
    expect(writesById(plan())["2026-W3"]).toBeUndefined();
  });

  it("refuses to apply once Pickems opened for the current week", () => {
    for (const status of ["picking", "locked", "scored"]) {
      expect(codeOf(() => plan({ weeks: season(status) }))).toBe("failed-precondition");
    }
  });

  it("works with no current week: past weeks pinned, later Selection weeks follow the league", () => {
    const result = plan({ currentWeekId: null });
    expect(result.currentWeekId).toBeNull();
    expect(writesById(result)).toEqual({
      "2026-W1": "ats",
      "2026-W2": "ats",
      "2026-W4": "ats",
      "2026-W6": null,
    });
    // W5 has no stored mode, so it already follows the league and needs no write.
  });

  it("treats an unminted current week as applied (it inherits when created)", () => {
    const result = plan({ currentWeekId: "2026-W7" });
    expect(result.currentWeekId).toBeNull();
    expect(result.currentWeekApplied).toBe(true);
  });
});

describe("planLeaguePickModeSwitch: start next week", () => {
  it("keeps the current week on the old mode during Selections", () => {
    const result = plan({ applyToCurrentWeek: false });
    expect(result.currentWeekApplied).toBe(false);
    expect(writesById(result)["2026-W5"]).toBe("ats");
    expect(writesById(result)["2026-W6"]).toBeNull();
  });

  it("keeps the current week on the old mode once Pickems opened", () => {
    for (const status of ["picking", "locked", "scored"]) {
      const result = plan({ applyToCurrentWeek: false, weeks: season(status) });
      expect(writesById(result)["2026-W5"]).toBe("ats");
    }
  });

  it("keeps a current week that already had its own mode", () => {
    const result = plan({
      applyToCurrentWeek: false,
      weeks: season("picking", "straightUp"),
    });
    expect(writesById(result)["2026-W5"]).toBeUndefined();
  });

  it("pins the old Straight Up mode when a Straight Up league moves to ATS", () => {
    const result = plan({ group: suLeague, newMode: "ats", applyToCurrentWeek: false, weeks: season("picking") });
    expect(writesById(result)).toEqual({
      "2026-W1": "straightUp",
      "2026-W2": "straightUp",
      "2026-W4": "straightUp",
      "2026-W5": "straightUp",
      "2026-W6": null,
    });
  });
});

describe("planLeaguePickModeSwitch: resolved modes after the switch", () => {
  it("scores past and current weeks as before and future weeks with the new mode", () => {
    const weeks = season("picking");
    const result = plan({ applyToCurrentWeek: false, weeks });
    const writes = writesById(result);
    const resolved = Object.fromEntries(
      weeks.map((w) => {
        const stored = w.id in writes ? writes[w.id] : w.data.pickMode;
        return [w.id, resolveWeekPickMode(stored ?? undefined, "straightUp")];
      })
    );
    expect(resolved).toEqual({
      "2026-W1": "ats",
      "2026-W2": "ats",
      "2026-W3": "straightUp",
      "2026-W4": "ats",
      "2026-W5": "ats",
      "2026-W6": "straightUp",
    });
    // A week minted later (no stored mode) follows the league.
    expect(resolveWeekPickMode(undefined, "straightUp")).toBe("straightUp");
  });

  it("is idempotent on retry", () => {
    const first = plan();
    const weeks = season("selection").map((w) => {
      const write = first.weekWrites.find((x) => x.id === w.id);
      if (!write) return w;
      const data = { ...w.data };
      if (write.pickMode) data.pickMode = write.pickMode;
      else delete data.pickMode;
      return { id: w.id, data };
    });
    const retry = plan({ group: suLeague, weeks });
    expect(retry.rulesNeedUpdate).toBe(false);
    expect(retry.weekWrites).toEqual([]);
  });
});

describe("weekOrder", () => {
  it("orders by season then week, null without numbers", () => {
    expect(weekOrder({ seasonYear: 2026, weekNumber: 5 })!).toBeLessThan(
      weekOrder({ seasonYear: 2027, weekNumber: 0 })!
    );
    expect(weekOrder({})).toBeNull();
  });
});
