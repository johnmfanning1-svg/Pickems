import {
  onSnapshot,
  queryEqual,
  refEqual,
  type DocumentData,
  type DocumentReference,
  type Query,
} from "firebase/firestore";
import { useEffect, useState } from "react";

/**
 * `onSnapshot` wrappers. Live listeners rather than one-shot reads: every
 * mutating action in the portal awaits the write and lets the listener report
 * the result, which is why no screen needs a manual refetch.
 */

/** Every doc carries its id and full path — the path is what audit entries record. */
export type WithId<T> = T & { id: string; path: string };

export interface QueryState<T> {
  data: WithId<T>[];
  loading: boolean;
  error: string | null;
}

/**
 * A `Query` is a fresh object on every render, so identity can't drive the
 * effect. `queryEqual` compares by value and only then swaps the stable copy —
 * the standard "derive state from changed props" adjustment.
 */
function useStableQuery(next: Query<DocumentData> | null): Query<DocumentData> | null {
  const [stable, setStable] = useState<Query<DocumentData> | null>(next);
  const changed =
    next == null || stable == null ? next !== stable : !queryEqual(next, stable);
  if (changed) setStable(next);
  return changed ? next : stable;
}

function useStableRef(
  next: DocumentReference<DocumentData> | null,
): DocumentReference<DocumentData> | null {
  const [stable, setStable] = useState<DocumentReference<DocumentData> | null>(next);
  const changed = next == null || stable == null ? next !== stable : !refEqual(next, stable);
  if (changed) setStable(next);
  return changed ? next : stable;
}

export function useCollection<T>(query: Query<DocumentData> | null): QueryState<T> {
  const stable = useStableQuery(query);
  const [state, setState] = useState<QueryState<T>>({
    data: [],
    loading: stable != null,
    error: null,
  });

  useEffect(() => {
    if (!stable) {
      setState({ data: [], loading: false, error: null });
      return;
    }
    setState((prev) => ({ ...prev, loading: true, error: null }));
    return onSnapshot(
      stable,
      (snapshot) => {
        setState({
          data: snapshot.docs.map(
            (doc) => ({ ...doc.data(), id: doc.id, path: doc.ref.path }) as WithId<T>,
          ),
          loading: false,
          error: null,
        });
      },
      (error) => setState({ data: [], loading: false, error: error.message }),
    );
  }, [stable]);

  return state;
}

export interface DocumentState<T> {
  data: WithId<T> | null;
  exists: boolean;
  loading: boolean;
  error: string | null;
}

export function useDocument<T>(ref: DocumentReference<DocumentData> | null): DocumentState<T> {
  const stable = useStableRef(ref);
  const [state, setState] = useState<DocumentState<T>>({
    data: null,
    exists: false,
    loading: stable != null,
    error: null,
  });

  useEffect(() => {
    if (!stable) {
      setState({ data: null, exists: false, loading: false, error: null });
      return;
    }
    setState((prev) => ({ ...prev, loading: true, error: null }));
    return onSnapshot(
      stable,
      (snapshot) => {
        setState({
          data: snapshot.exists()
            ? ({ ...snapshot.data(), id: snapshot.id, path: snapshot.ref.path } as WithId<T>)
            : null,
          exists: snapshot.exists(),
          loading: false,
          error: null,
        });
      },
      (error) => setState({ data: null, exists: false, loading: false, error: error.message }),
    );
  }, [stable]);

  return state;
}
