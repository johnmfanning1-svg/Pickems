import { useCallback, useState } from "react";
import { describeError } from "@/lib/callables";

/**
 * Runs one mutating action at a time and tracks which one, so a table of rows
 * can each show their own pending state without a state variable per row.
 *
 * Deliberately not optimistic: the action awaits the write, and the page's
 * `onSnapshot` listeners report the result. A failed write therefore never
 * leaves the screen showing a change that did not happen.
 */
export function useAction() {
  const [pendingKey, setPendingKey] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const run = useCallback(
    async (key: string, action: () => Promise<string | void>): Promise<boolean> => {
      setPendingKey(key);
      setError(null);
      setMessage(null);
      try {
        const result = await action();
        if (typeof result === "string") setMessage(result);
        return true;
      } catch (caught) {
        setError(describeError(caught));
        return false;
      } finally {
        setPendingKey(null);
      }
    },
    [],
  );

  const isPending = useCallback((key: string) => pendingKey === key, [pendingKey]);

  return {
    run,
    isPending,
    busy: pendingKey != null,
    error,
    message,
    clearError: useCallback(() => setError(null), []),
    clearMessage: useCallback(() => setMessage(null), []),
  };
}
