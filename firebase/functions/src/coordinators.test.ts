import { describe, it, expect } from "vitest";
import { HttpsError } from "firebase-functions/v2/https";
import { shouldSendDeadlinePush } from "./deadlinePushPrefs";
import {
  activeCoordinatorRole,
  assertWeekOperator,
  classifyLeagueCaller,
  coordinatorPushCopy,
  coordinatorRoleChanges,
  coordinatorsAfterCommissionerTransfer,
  leagueAdminAllowed,
  sanitizeCoordinators,
  weekOperationAllowed,
  type LeagueAuthGroup,
  type LeagueCallerKind,
} from "./coordinators";

const group = (overrides: Partial<LeagueAuthGroup> = {}): LeagueAuthGroup => ({
  commissionerId: "comm",
  memberIds: ["comm", "oc", "dc", "member"],
  name: "Saturday League",
  coordinators: { oc: "oc", dc: "dc" },
  ...overrides,
});

function codeOf(fn: () => unknown): string | undefined {
  try {
    fn();
  } catch (error) {
    return error instanceof HttpsError ? error.code : "not-https-error";
  }
  return undefined;
}

describe("classifyLeagueCaller", () => {
  it("ranks admin, then commissioner, then a current coordinator", () => {
    expect(classifyLeagueCaller({ callerUid: "oc", callerIsAdmin: true, group: group() })).toBe("admin");
    expect(classifyLeagueCaller({ callerUid: "comm", callerIsAdmin: false, group: group() })).toBe(
      "commissioner"
    );
    expect(classifyLeagueCaller({ callerUid: "oc", callerIsAdmin: false, group: group() })).toBe(
      "coordinator"
    );
    expect(classifyLeagueCaller({ callerUid: "dc", callerIsAdmin: false, group: group() })).toBe(
      "coordinator"
    );
    expect(classifyLeagueCaller({ callerUid: "member", callerIsAdmin: false, group: group() })).toBe(
      "member"
    );
    expect(classifyLeagueCaller({ callerUid: "outsider", callerIsAdmin: false, group: group() })).toBe(
      "outsider"
    );
    expect(classifyLeagueCaller({ callerUid: "oc", callerIsAdmin: false, group: undefined })).toBe(
      "outsider"
    );
  });

  it("ignores a stale seat held by the commissioner or someone off the roster", () => {
    const stale = group({
      coordinators: { oc: "comm", dc: "gone" },
      memberIds: ["comm", "member"],
    });
    expect(activeCoordinatorRole(stale, "comm")).toBeNull();
    expect(activeCoordinatorRole(stale, "gone")).toBeNull();
    expect(classifyLeagueCaller({ callerUid: "comm", callerIsAdmin: false, group: stale })).toBe(
      "commissioner"
    );
    expect(classifyLeagueCaller({ callerUid: "gone", callerIsAdmin: false, group: stale })).toBe(
      "outsider"
    );
    expect(classifyLeagueCaller({ callerUid: "member", callerIsAdmin: false, group: group({ coordinators: undefined }) })).toBe(
      "member"
    );
  });
});

describe("week operations versus league admin", () => {
  const kinds: LeagueCallerKind[] = ["admin", "commissioner", "coordinator", "member", "outsider"];

  it("lets a coordinator run the week and keeps league admin to the commissioner", () => {
    expect(kinds.filter(weekOperationAllowed)).toEqual(["admin", "commissioner", "coordinator"]);
    expect(kinds.filter(leagueAdminAllowed)).toEqual(["admin", "commissioner"]);
  });

  it("assertWeekOperator accepts the operator set and rejects everyone else", () => {
    expect(codeOf(() => assertWeekOperator({ callerUid: "oc", callerIsAdmin: false, group: undefined }))).toBe(
      "not-found"
    );
    expect(codeOf(() => assertWeekOperator({ callerUid: "member", callerIsAdmin: false, group: group() }))).toBe(
      "permission-denied"
    );
    expect(codeOf(() => assertWeekOperator({ callerUid: "outsider", callerIsAdmin: false, group: group() }))).toBe(
      "permission-denied"
    );
    expect(codeOf(() => assertWeekOperator({ callerUid: "comm", callerIsAdmin: false, group: group() }))).toBeUndefined();
    expect(codeOf(() => assertWeekOperator({ callerUid: "oc", callerIsAdmin: false, group: group() }))).toBeUndefined();
    expect(codeOf(() => assertWeekOperator({ callerUid: "dc", callerIsAdmin: false, group: group() }))).toBeUndefined();
    expect(
      codeOf(() => assertWeekOperator({ callerUid: "support", callerIsAdmin: true, group: group() }))
    ).toBeUndefined();
  });
});

describe("coordinatorRoleChanges", () => {
  it("notifies an appointment, a removal, and a swap", () => {
    expect(coordinatorRoleChanges(undefined, { oc: "oc" }, "comm")).toEqual([
      { userId: "oc", role: "oc", change: "appointed" },
    ]);
    expect(coordinatorRoleChanges({ dc: "dc" }, {}, "comm")).toEqual([
      { userId: "dc", role: "dc", change: "removed" },
    ]);
    expect(coordinatorRoleChanges({ oc: "oc", dc: "dc" }, { oc: "dc", dc: "oc" }, "comm")).toEqual([
      { userId: "oc", role: "oc", change: "removed" },
      { userId: "dc", role: "oc", change: "appointed" },
      { userId: "dc", role: "dc", change: "removed" },
      { userId: "oc", role: "dc", change: "appointed" },
    ]);
    expect(coordinatorRoleChanges({ oc: "oc", dc: "dc" }, { oc: "oc", dc: "dc" }, "comm")).toEqual([]);
  });

  it("skips the notice when that person was just made commissioner", () => {
    expect(coordinatorRoleChanges({ oc: "oc", dc: "dc" }, { dc: "dc" }, "oc")).toEqual([]);
    expect(coordinatorRoleChanges({ oc: "oc" }, { oc: "oc" }, "oc")).toEqual([]);
  });
});

describe("coordinator push copy", () => {
  it("names the seat and falls back when the league name is missing", () => {
    expect(coordinatorPushCopy({ change: "appointed", role: "oc", leagueName: "  Saturday   League " })).toEqual({
      title: "You're the OC",
      body: "Saturday League appointed you Offensive Coordinator. You can run the week if the commissioner is unavailable.",
    });
    expect(coordinatorPushCopy({ change: "removed", role: "dc", leagueName: "" })).toEqual({
      title: "DC role removed",
      body: "You're no longer the Defensive Coordinator in League.",
    });
    expect(shouldSendDeadlinePush({ notifyPickemsDeadlines: false }, "coordinator_role")).toBe(true);
  });
});

describe("sanitizeCoordinators", () => {
  it("leaves a valid map alone", () => {
    expect(sanitizeCoordinators(group())).toEqual({ action: "none" });
  });

  it("drops a seat whose holder left, became commissioner, or is duplicated", () => {
    expect(
      sanitizeCoordinators(group({ memberIds: ["comm", "dc", "member"], coordinators: { oc: "oc", dc: "dc" } }))
    ).toEqual({ action: "set", value: { dc: "dc" } });
    expect(
      sanitizeCoordinators(group({ coordinators: { oc: "comm", dc: "dc" } }))
    ).toEqual({ action: "set", value: { dc: "dc" } });
    expect(
      sanitizeCoordinators(group({ coordinators: { oc: "oc", dc: "oc" } }))
    ).toEqual({ action: "set", value: { oc: "oc" } });
    expect(
      sanitizeCoordinators(group({ memberIds: ["comm", "member"], coordinators: { oc: "oc" } }))
    ).toEqual({ action: "delete" });
    expect(sanitizeCoordinators(group({ coordinators: undefined }))).toEqual({ action: "none" });
  });

  it("clears the new commissioner and keeps the other seat on transfer", () => {
    expect(coordinatorsAfterCommissionerTransfer(group(), "oc")).toEqual({
      action: "set",
      value: { dc: "dc" },
    });
    expect(coordinatorsAfterCommissionerTransfer(group({ coordinators: { oc: "oc" } }), "oc")).toEqual({
      action: "delete",
    });
    expect(coordinatorsAfterCommissionerTransfer(group(), "member")).toEqual({ action: "none" });
  });
});
