import { useCallback, useRef, useState, type ReactNode } from "react";
import { Button } from "./Button";

export interface ConfirmOptions {
  title: string;
  body?: ReactNode;
  confirmLabel?: string;
  tone?: "danger" | "primary";
  /**
   * When set, the operator must type this string verbatim to enable the confirm
   * button. Used for destructive actions so the dialog names the target and the
   * target has to be acknowledged, not just clicked past.
   */
  requireText?: string;
}

/**
 * Promise-based confirmation. Every mutating action in the portal awaits this
 * first, so "are you sure" is one line at the call site rather than a bespoke
 * modal per page.
 */
export function useConfirm(): { confirm: (options: ConfirmOptions) => Promise<boolean>; dialog: ReactNode } {
  const [options, setOptions] = useState<ConfirmOptions | null>(null);
  const [typed, setTyped] = useState("");
  const resolver = useRef<((value: boolean) => void) | null>(null);

  const confirm = useCallback((next: ConfirmOptions) => {
    setTyped("");
    setOptions(next);
    return new Promise<boolean>((resolve) => {
      resolver.current = resolve;
    });
  }, []);

  const settle = useCallback((value: boolean) => {
    resolver.current?.(value);
    resolver.current = null;
    setOptions(null);
    setTyped("");
  }, []);

  const dialog = options ? (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={options.title}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
      onKeyDown={(event) => {
        if (event.key === "Escape") settle(false);
      }}
    >
      <div className="w-full max-w-md rounded-xl border border-ink-600 bg-ink-800 p-5 shadow-2xl">
        <h2 className="text-base font-semibold text-slate-50">{options.title}</h2>
        {options.body ? <div className="mt-2 text-sm text-slate-300">{options.body}</div> : null}
        {options.requireText ? (
          <label className="mt-4 block space-y-1">
            <span className="block text-xs text-slate-400">
              Type <code className="rounded bg-ink-900 px-1 font-mono text-slate-200">{options.requireText}</code> to
              confirm
            </span>
            <input
              autoFocus
              value={typed}
              onChange={(event) => setTyped(event.target.value)}
              className="w-full rounded-md border border-ink-600 bg-ink-900 px-3 py-1.5 text-sm text-slate-100 focus:border-brand focus:outline-none"
            />
          </label>
        ) : null}
        <div className="mt-5 flex justify-end gap-2">
          <Button variant="ghost" onClick={() => settle(false)}>
            Cancel
          </Button>
          <Button
            variant={options.tone === "primary" ? "primary" : "danger"}
            disabled={options.requireText != null && typed.trim() !== options.requireText}
            onClick={() => settle(true)}
          >
            {options.confirmLabel ?? "Confirm"}
          </Button>
        </div>
      </div>
    </div>
  ) : null;

  return { confirm, dialog };
}
