import {
  collection,
  collectionGroup,
  doc,
  limit,
  orderBy,
  query,
  where,
} from "firebase/firestore";
import { useMemo } from "react";
import { db } from "@/lib/firebase";
import type {
  AppConfigDoc,
  AuditEntryDoc,
  ChatMessageDoc,
  GroupDoc,
  MemberDoc,
  NominationDoc,
  PickDoc,
  SlateGameDoc,
  SubmissionDoc,
  UserDoc,
  WeekDoc,
} from "@/lib/types";
import { useCollection, useDocument, type QueryState, type WithId } from "./useFirestore";

/**
 * Domain queries.
 *
 * Ordering is done client-side rather than with `orderBy`: a Firestore `orderBy`
 * silently drops documents missing that field, and a doc with a missing field is
 * exactly what an ops console exists to find.
 */

export function useGroups(): QueryState<GroupDoc> {
  const state = useCollection<GroupDoc>(useMemo(() => collection(db, "groups"), []));
  return useMemo(
    () => ({
      ...state,
      data: [...state.data].sort((a, b) => (a.name ?? "").localeCompare(b.name ?? "")),
    }),
    [state],
  );
}

export function useGroup(groupId: string | undefined) {
  return useDocument<GroupDoc>(useMemo(() => (groupId ? doc(db, "groups", groupId) : null), [groupId]));
}

export function useMembers(groupId: string | undefined): QueryState<MemberDoc> {
  const state = useCollection<MemberDoc>(
    useMemo(() => (groupId ? collection(db, "groups", groupId, "members") : null), [groupId]),
  );
  return useMemo(
    () => ({
      ...state,
      data: [...state.data].sort((a, b) => (a.displayName ?? "").localeCompare(b.displayName ?? "")),
    }),
    [state],
  );
}

/** Newest week first — season then ESPN week number, not doc id (ids sort "W10" before "W2"). */
export function useWeeks(groupId: string | undefined): QueryState<WeekDoc> {
  const state = useCollection<WeekDoc>(
    useMemo(() => (groupId ? collection(db, "groups", groupId, "weeks") : null), [groupId]),
  );
  return useMemo(
    () => ({
      ...state,
      data: [...state.data].sort(
        (a, b) => (b.seasonYear ?? 0) - (a.seasonYear ?? 0) || (b.weekNumber ?? 0) - (a.weekNumber ?? 0),
      ),
    }),
    [state],
  );
}

export function useWeek(groupId: string | undefined, weekId: string | undefined) {
  return useDocument<WeekDoc>(
    useMemo(
      () => (groupId && weekId ? doc(db, "groups", groupId, "weeks", weekId) : null),
      [groupId, weekId],
    ),
  );
}

export function useSlateGames(
  groupId: string | undefined,
  weekId: string | undefined,
): QueryState<SlateGameDoc> {
  const state = useCollection<SlateGameDoc>(
    useMemo(
      () =>
        groupId && weekId
          ? collection(db, "groups", groupId, "weeks", weekId, "games")
          : null,
      [groupId, weekId],
    ),
  );
  return useMemo(
    () => ({
      ...state,
      data: [...state.data].sort(
        (a, b) => (a.kickoff?.toMillis() ?? 0) - (b.kickoff?.toMillis() ?? 0),
      ),
    }),
    [state],
  );
}

export function useNominations(
  groupId: string | undefined,
  weekId: string | undefined,
): QueryState<NominationDoc> {
  return useCollection<NominationDoc>(
    useMemo(
      () =>
        groupId && weekId
          ? collection(db, "groups", groupId, "weeks", weekId, "nominations")
          : null,
      [groupId, weekId],
    ),
  );
}

export function usePicks(
  groupId: string | undefined,
  weekId: string | undefined,
): QueryState<PickDoc> {
  return useCollection<PickDoc>(
    useMemo(
      () =>
        groupId && weekId ? collection(db, "groups", groupId, "weeks", weekId, "picks") : null,
      [groupId, weekId],
    ),
  );
}

export function useSubmissions(
  groupId: string | undefined,
  weekId: string | undefined,
): QueryState<SubmissionDoc> {
  return useCollection<SubmissionDoc>(
    useMemo(
      () =>
        groupId && weekId
          ? collection(db, "groups", groupId, "weeks", weekId, "submissions")
          : null,
      [groupId, weekId],
    ),
  );
}

export function useAppConfig() {
  return useDocument<AppConfigDoc>(useMemo(() => doc(db, "appConfig", "live"), []));
}

/**
 * `adminAudit`, newest first. Filtering by action uses the
 * (action ASC, createdAt DESC) composite index from `firestore.indexes.json`.
 */
export function useAuditLog(action: string | null, max = 200): QueryState<AuditEntryDoc> {
  return useCollection<AuditEntryDoc>(
    useMemo(() => {
      const base = collection(db, "adminAudit");
      return action
        ? query(base, where("action", "==", action), orderBy("createdAt", "desc"), limit(max))
        : query(base, orderBy("createdAt", "desc"), limit(max));
    }, [action, max]),
  );
}

/**
 * Reported messages across every group.
 *
 * Two constraints shape this query. Firestore requires the inequality field to
 * be the first `orderBy`, so `reportCount` is ordered explicitly. And an index
 * is only traversable forwards or fully reversed, so (reportCount ASC,
 * createdAt DESC) — the index Lane F declared — cannot serve `reportCount DESC,
 * createdAt DESC`. Hence ascending here, with the most-reported-first ordering
 * an operator actually wants applied client-side.
 */
export function useReportedMessages(max = 200): QueryState<ChatMessageDoc> {
  const state = useCollection<ChatMessageDoc>(
    useMemo(
      () =>
        query(
          collectionGroup(db, "messages"),
          where("reportCount", ">", 0),
          orderBy("reportCount", "asc"),
          orderBy("createdAt", "desc"),
          limit(max),
        ),
      [max],
    ),
  );
  return useMemo(
    () => ({
      ...state,
      data: [...state.data].sort(
        (a, b) =>
          (b.reportCount ?? 0) - (a.reportCount ?? 0) ||
          (b.createdAt?.toMillis() ?? 0) - (a.createdAt?.toMillis() ?? 0),
      ),
    }),
    [state],
  );
}

export function useUser(userId: string | null) {
  return useDocument<UserDoc>(useMemo(() => (userId ? doc(db, "users", userId) : null), [userId]));
}

/** Convenience for the member × pick join on the week picks grid. */
export function pickForUser(
  picks: WithId<PickDoc>[],
  userId: string,
): WithId<PickDoc> | undefined {
  return picks.find((pick) => pick.id === userId || pick.userId === userId);
}
