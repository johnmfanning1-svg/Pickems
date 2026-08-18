import { FirebaseError } from "firebase/app";
import { httpsCallable } from "firebase/functions";
import { functions } from "./firebase";
import type { WeekAuditRow, WeekStatus } from "./types";

/**
 * Typed wrappers over the v2 `onCall` functions in
 * `firebase/functions/src/admin.ts`. Each of those asserts the `admin` claim and
 * writes its own `adminAudit` entry, so callers here must not double-log.
 */

function callable<Request, Response>(name: string) {
  const fn = httpsCallable<Request, Response>(functions, name);
  return async (data: Request): Promise<Response> => {
    const result = await fn(data);
    return result.data;
  };
}

export const setAdminRole = callable<
  { uid?: string; email?: string; admin: boolean },
  { uid: string; email: string | null; admin: boolean; note: string }
>("setAdminRole");

export const adminSetWeekStatus = callable<
  { groupId: string; weekId: string; status: WeekStatus; pickDeadline?: string | null },
  { groupId: string; weekId: string; status: WeekStatus; materialized: unknown }
>("adminSetWeekStatus");

export const adminRematerializeNominations = callable<
  { groupId: string; weekId: string; force?: boolean },
  { groupId: string; weekId: string; [key: string]: unknown }
>("adminRematerializeNominations");

export const adminUpsertPick = callable<
  {
    groupId: string;
    weekId: string;
    userId: string;
    picks: Record<string, string>;
    isLocked?: boolean;
    confidenceGameId?: string | null;
  },
  { groupId: string; weekId: string; userId: string; pickCount: number; isLocked: boolean }
>("adminUpsertPick");

export const adminRemoveMember = callable<
  { groupId: string; userId: string },
  { groupId: string; userId: string; weeksCleaned: number }
>("adminRemoveMember");

export const adminTransferCommissioner = callable<
  { groupId: string; userId: string },
  { groupId: string; commissionerId: string; previousCommissionerId: string | null }
>("adminTransferCommissioner");

export const adminAuditWeekIds = callable<
  { groupId?: string; seasonYear?: number },
  { groupsScanned: number; rows: WeekAuditRow[] }
>("adminAuditWeekIds");

export const adminRescoreWeek = callable<
  { groupId: string; weekId: string },
  { groupId: string; weekId: string; weeksSummed: number; entries: unknown[] }
>("adminRescoreWeek");

export const adminMigrateWeek0Split = callable<
  { dryRun?: boolean; groupId?: string },
  {
    dryRun: boolean;
    groups: Array<{
      groupId: string;
      groupName: string | null;
      skipped: boolean;
      skipReason?: string;
      weekZeroGames: number;
      movedNominations: number;
      movedPickDocs: number;
      deletedWeekOneGames: number;
      clearedSubmissions: number;
      weekOnePickDeadline: string | null;
    }>;
  }
>("adminMigrateWeek0Split");

/**
 * Turns Firebase's error surface into something an operator can act on.
 * `permission-denied` from a callable means the claim is stale far more often
 * than it means the account lost access, so say so.
 */
export function describeError(error: unknown): string {
  if (error instanceof FirebaseError) {
    switch (error.code) {
      case "functions/permission-denied":
      case "permission-denied":
        return "Permission denied. Your admin claim may be stale — sign out and back in, then retry.";
      case "functions/unauthenticated":
      case "unauthenticated":
        return "Your session expired. Sign in again.";
      case "functions/not-found":
        return "That callable is not deployed. Run `firebase deploy --only functions`.";
      case "functions/internal":
        return `The function failed: ${error.message}`;
      case "failed-precondition":
      case "functions/failed-precondition":
        return error.message;
      default:
        return `${error.code}: ${error.message}`;
    }
  }
  if (error instanceof Error) return error.message;
  return String(error);
}
