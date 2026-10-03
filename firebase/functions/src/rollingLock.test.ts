import { describe, it, expect } from "vitest";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import {
  earliestStampedKickoffMillis,
  latestStampedKickoffMillis,
  planRollingSwitch,
  rollingWeekUpdate,
  weekInProgress,
  type RollingWeekData,
} from "./rollingLock";

const ts = (iso: string) => Timestamp.fromDate(new Date(iso));

/** Shape of Core 4 OG 2026-W5 right before the 2026-10-02 hand repair. */
function core4LockedWeek(): RollingWeekData {
  return {
    status: "locked",
    pickLockMode: "firstKickoff",
    weekLockAt: ts("2026-10-03T00:00:00Z"),
    lockedAt: ts("2026-10-03T00:03:07.584Z"),
    gameKickoffs: {
      "401858476": ts("2026-10-03T00:00:00Z"),
      "401862791": ts("2026-10-03T16:00:00Z"),
      "401856708": ts("2026-10-03T19:30:00Z"),
      "401858249": ts("2026-10-03T23:30:00Z"),
      "401860921": ts("2026-10-04T01:30:00Z"),
    },
  };
}

const friday820pm = Date.parse("2026-10-03T00:20:00Z");
const commissioner = { commissionerId: "comm", rules: { pickDeadline: "firstKickoff" } };

function codeOf(fn: () => unknown): string | undefined {
  try {
    fn();
  } catch (error) {
    return error instanceof HttpsError ? error.code : "not-https-error";
  }
  return undefined;
}

describe("stamped kickoff helpers", () => {
  it("reads first and last kickoff from gameKickoffs", () => {
    const week = core4LockedWeek();
    expect(earliestStampedKickoffMillis(week)).toBe(Date.parse("2026-10-03T00:00:00Z"));
    expect(latestStampedKickoffMillis(week)).toBe(Date.parse("2026-10-04T01:30:00Z"));
  });

  it("returns null with no readable kickoffs", () => {
    expect(latestStampedKickoffMillis({ gameKickoffs: {} })).toBeNull();
    expect(latestStampedKickoffMillis({ gameKickoffs: { a: "soon" } })).toBeNull();
    expect(latestStampedKickoffMillis({})).toBeNull();
  });
});

describe("weekInProgress", () => {
  it("treats a locked week as in progress", () => {
    expect(weekInProgress(core4LockedWeek(), friday820pm)).toBe(true);
  });

  it("treats a picking week as in progress only after its first kickoff", () => {
    const week = { ...core4LockedWeek(), status: "picking", lockedAt: undefined };
    expect(weekInProgress(week, Date.parse("2026-10-02T23:59:00Z"))).toBe(false);
    expect(weekInProgress(week, friday820pm)).toBe(true);
  });

  it("never treats selection or scored weeks as in progress", () => {
    expect(weekInProgress({ ...core4LockedWeek(), status: "selection" }, friday820pm)).toBe(false);
    expect(weekInProgress({ ...core4LockedWeek(), status: "scored" }, friday820pm)).toBe(false);
  });
});

describe("planRollingSwitch", () => {
  it("applies to the current week with weekLockAt = latest kickoff (Core 4 OG W5)", () => {
    const plan = planRollingSwitch({
      nowMs: friday820pm,
      callerUid: "comm",
      callerIsAdmin: false,
      group: commissioner,
      applyToCurrentWeek: true,
      week: core4LockedWeek(),
    });
    expect(plan.rulesNeedUpdate).toBe(true);
    expect(plan.week).toEqual({
      needsUpdate: true,
      weekLockAtMs: Date.parse("2026-10-04T01:30:00Z"),
    });
  });

  it("writes exactly the four week fields from the hand repair", () => {
    const update = rollingWeekUpdate(Date.parse("2026-10-04T01:30:00Z"));
    expect(Object.keys(update).sort()).toEqual(["lockedAt", "pickLockMode", "status", "weekLockAt"]);
    expect(update.pickLockMode).toBe("rolling");
    expect(update.status).toBe("picking");
    expect((update.weekLockAt as Timestamp).toDate().toISOString()).toBe(
      "2026-10-04T01:30:00.000Z"
    );
    expect(update.lockedAt).toEqual(FieldValue.delete());
  });

  it("only changes the league rule when the commissioner says No", () => {
    const plan = planRollingSwitch({
      nowMs: friday820pm,
      callerUid: "comm",
      callerIsAdmin: false,
      group: commissioner,
      applyToCurrentWeek: false,
      week: core4LockedWeek(),
    });
    expect(plan).toEqual({ rulesNeedUpdate: true, week: null });
  });

  it("is idempotent once the league and week are already rolling", () => {
    const plan = planRollingSwitch({
      nowMs: friday820pm,
      callerUid: "comm",
      callerIsAdmin: false,
      group: { commissionerId: "comm", rules: { pickDeadline: "rolling" } },
      applyToCurrentWeek: true,
      week: {
        ...core4LockedWeek(),
        status: "picking",
        pickLockMode: "rolling",
        weekLockAt: ts("2026-10-04T01:30:00Z"),
        lockedAt: undefined,
      },
    });
    expect(plan).toEqual({ rulesNeedUpdate: false, week: { needsUpdate: false, weekLockAtMs: null } });
  });

  it("leaves an already-rolling week alone even if it is locked", () => {
    const plan = planRollingSwitch({
      nowMs: friday820pm,
      callerUid: "comm",
      callerIsAdmin: false,
      group: commissioner,
      applyToCurrentWeek: true,
      week: { ...core4LockedWeek(), pickLockMode: "rolling" },
    });
    expect(plan.week?.needsUpdate).toBe(false);
  });

  it("refuses non-commissioners and allows super admins", () => {
    const base = {
      nowMs: friday820pm,
      group: commissioner,
      applyToCurrentWeek: true,
      week: core4LockedWeek(),
    };
    expect(codeOf(() => planRollingSwitch({ ...base, callerUid: "member", callerIsAdmin: false }))).toBe(
      "permission-denied"
    );
    expect(
      codeOf(() => planRollingSwitch({ ...base, callerUid: "someone", callerIsAdmin: true }))
    ).toBeUndefined();
  });

  it("refuses a missing league or week", () => {
    expect(
      codeOf(() =>
        planRollingSwitch({
          nowMs: friday820pm,
          callerUid: "comm",
          callerIsAdmin: false,
          group: undefined,
          applyToCurrentWeek: false,
        })
      )
    ).toBe("not-found");
    expect(
      codeOf(() =>
        planRollingSwitch({
          nowMs: friday820pm,
          callerUid: "comm",
          callerIsAdmin: false,
          group: commissioner,
          applyToCurrentWeek: true,
        })
      )
    ).toBe("not-found");
  });

  it("refuses a scored week", () => {
    expect(
      codeOf(() =>
        planRollingSwitch({
          nowMs: friday820pm,
          callerUid: "comm",
          callerIsAdmin: false,
          group: commissioner,
          applyToCurrentWeek: true,
          week: { ...core4LockedWeek(), status: "scored" },
        })
      )
    ).toBe("failed-precondition");
  });

  it("refuses a selection week, a week with no kickoffs, and a week whose games have all started", () => {
    const base = {
      nowMs: friday820pm,
      callerUid: "comm",
      callerIsAdmin: false,
      group: commissioner,
      applyToCurrentWeek: true,
    };
    expect(codeOf(() => planRollingSwitch({ ...base, week: { status: "selection" } }))).toBe(
      "failed-precondition"
    );
    expect(
      codeOf(() => planRollingSwitch({ ...base, week: { status: "locked", gameKickoffs: {} } }))
    ).toBe("failed-precondition");
    expect(
      codeOf(() =>
        planRollingSwitch({
          ...base,
          nowMs: Date.parse("2026-10-04T01:30:00Z"),
          week: core4LockedWeek(),
        })
      )
    ).toBe("failed-precondition");
  });

  it("allows applying to a picking week before any game starts", () => {
    const plan = planRollingSwitch({
      nowMs: Date.parse("2026-10-02T12:00:00Z"),
      callerUid: "comm",
      callerIsAdmin: false,
      group: commissioner,
      applyToCurrentWeek: true,
      week: { ...core4LockedWeek(), status: "picking", lockedAt: undefined },
    });
    expect(plan.week?.needsUpdate).toBe(true);
  });
});
