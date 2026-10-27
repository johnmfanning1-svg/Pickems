import { FieldValue } from "firebase-admin/firestore";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { sendToUser } from "./notifications";
import { alertCollapseId, leagueDisplayName, leagueThreadId } from "./pushAlert";

export type CoordinatorSeat = "oc" | "dc";

export interface LeagueAuthGroup {
  commissionerId?: unknown;
  memberIds?: unknown;
  coordinators?: unknown;
  name?: unknown;
}

export type LeagueCallerKind = "admin" | "commissioner" | "coordinator" | "member" | "outsider";

export interface CoordinatorNotice {
  userId: string;
  role: CoordinatorSeat;
  change: "appointed" | "removed";
}

export type CoordinatorMapUpdate =
  | { action: "none" }
  | { action: "delete" }
  | { action: "set"; value: { oc?: string; dc?: string } };

function rawSlot(value: unknown, key: CoordinatorSeat): string | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const slot = (value as Record<string, unknown>)[key];
  return typeof slot === "string" && slot.length > 0 ? slot : undefined;
}

export function coordinatorSlots(value: unknown): { oc?: string; dc?: string } {
  return { oc: rawSlot(value, "oc"), dc: rawSlot(value, "dc") };
}

function memberList(memberIds: unknown): string[] {
  if (!Array.isArray(memberIds)) return [];
  return memberIds.filter((id): id is string => typeof id === "string" && id.length > 0);
}

/** Active seat for this uid. The commissioner and anyone off the roster do not count. */
export function activeCoordinatorRole(
  group: LeagueAuthGroup | undefined,
  uid: string
): CoordinatorSeat | null {
  if (!group || typeof group.commissionerId !== "string") return null;
  if (group.commissionerId === uid) return null;
  if (!memberList(group.memberIds).includes(uid)) return null;
  const slots = coordinatorSlots(group.coordinators);
  if (slots.oc === uid) return "oc";
  if (slots.dc === uid) return "dc";
  return null;
}

export function classifyLeagueCaller(input: {
  callerUid: string;
  callerIsAdmin: boolean;
  group: LeagueAuthGroup | undefined;
}): LeagueCallerKind {
  if (input.callerIsAdmin) return "admin";
  if (!input.group) return "outsider";
  if (input.group.commissionerId === input.callerUid) return "commissioner";
  if (activeCoordinatorRole(input.group, input.callerUid)) return "coordinator";
  if (memberList(input.group.memberIds).includes(input.callerUid)) return "member";
  return "outsider";
}

/** Week-status callables such as `adminSetWeekStatus`. */
export function weekOperationAllowed(kind: LeagueCallerKind): boolean {
  return kind === "admin" || kind === "commissioner" || kind === "coordinator";
}

/** League ownership and scoring settings. Coordinators are rejected. */
export function leagueAdminAllowed(kind: LeagueCallerKind): boolean {
  return kind === "admin" || kind === "commissioner";
}

export function assertWeekOperator(input: {
  callerUid: string;
  callerIsAdmin: boolean;
  group: LeagueAuthGroup | undefined;
}): void {
  if (!input.group) {
    throw new HttpsError("not-found", "League not found.");
  }
  const kind = classifyLeagueCaller(input);
  if (!weekOperationAllowed(kind)) {
    throw new HttpsError(
      "permission-denied",
      "Only the commissioner or a coordinator can do that."
    );
  }
}

/**
 * Seat changes between two stored maps.
 * A removal is skipped when that uid is now the commissioner (they were promoted).
 */
export function coordinatorRoleChanges(
  before: unknown,
  after: unknown,
  commissionerId?: unknown
): CoordinatorNotice[] {
  const previous = coordinatorSlots(before);
  const next = coordinatorSlots(after);
  const promoted = typeof commissionerId === "string" ? commissionerId : undefined;
  const notices: CoordinatorNotice[] = [];
  for (const role of ["oc", "dc"] as const) {
    const from = previous[role];
    const to = next[role];
    if (from === to) continue;
    if (from && from !== promoted) {
      notices.push({ userId: from, role, change: "removed" });
    }
    if (to && to !== promoted) {
      notices.push({ userId: to, role, change: "appointed" });
    }
  }
  return notices;
}

export function coordinatorPushCopy(input: {
  change: "appointed" | "removed";
  role: CoordinatorSeat;
  leagueName: unknown;
}): { title: string; body: string } {
  const titleRole = input.role === "oc" ? "Offensive Coordinator" : "Defensive Coordinator";
  const short = input.role === "oc" ? "OC" : "DC";
  const league = leagueDisplayName(input.leagueName);
  if (input.change === "appointed") {
    return {
      title: `You're the ${short}`,
      body: `${league} appointed you ${titleRole}. You can run the week if the commissioner is unavailable.`,
    };
  }
  return {
    title: `${short} role removed`,
    body: `You're no longer the ${titleRole} in ${league}.`,
  };
}

/** Drop seats that are empty, the commissioner, off the roster, or the same person twice. */
export function sanitizeCoordinators(group: LeagueAuthGroup): CoordinatorMapUpdate {
  const current = coordinatorSlots(group.coordinators);
  const members = memberList(group.memberIds);
  const commissionerId = typeof group.commissionerId === "string" ? group.commissionerId : "";
  const keep = (id: string | undefined) =>
    id && id !== commissionerId && members.includes(id) ? id : undefined;
  let oc = keep(current.oc);
  let dc = keep(current.dc);
  if (oc && dc && oc === dc) dc = undefined;
  if (oc === current.oc && dc === current.dc) return { action: "none" };
  if (!oc && !dc) return { action: "delete" };
  const value: { oc?: string; dc?: string } = {};
  if (oc) value.oc = oc;
  if (dc) value.dc = dc;
  return { action: "set", value };
}

/** Drop a seat when its holder becomes commissioner. Compares against the stored map. */
export function coordinatorsAfterCommissionerTransfer(
  group: LeagueAuthGroup,
  newCommissionerId: string
): CoordinatorMapUpdate {
  return sanitizeCoordinators({ ...group, commissionerId: newCommissionerId });
}

/**
 * Push when a coordinator seat changes, and drop a seat whose holder left
 * or became commissioner. The cleanup write re-enters this trigger, which
 * is what sends the removal when an older client only updated `memberIds`.
 */
export const onCoordinatorRolesChanged = onDocumentUpdated(
  "groups/{groupId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const groupId = event.params.groupId;
    const changes = coordinatorRoleChanges(before.coordinators, after.coordinators, after.commissionerId);
    if (changes.length > 0) {
      const leagueName = after.name;
      await Promise.all(
        changes.map(async (change) => {
          const copy = coordinatorPushCopy({ ...change, leagueName });
          await sendToUser(
            change.userId,
            copy.title,
            copy.body,
            "coordinator_role",
            {
              groupId,
              role: change.role,
              change: change.change,
            },
            undefined,
            {
              subtitle: leagueDisplayName(leagueName),
              threadId: leagueThreadId(groupId),
              collapseId: alertCollapseId(
                groupId,
                "coordinator",
                `${change.change}:${change.role}:${change.userId}`
              ),
            }
          );
        })
      );
    }

    const sanitized = sanitizeCoordinators(after as LeagueAuthGroup);
    if (sanitized.action === "none") return;
    const ref = event.data?.after.ref;
    if (!ref) return;
    if (sanitized.action === "delete") {
      await ref.update({ coordinators: FieldValue.delete() });
      return;
    }
    await ref.update({ coordinators: sanitized.value });
  }
);
