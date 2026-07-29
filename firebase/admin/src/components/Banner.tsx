import type { ReactNode } from "react";

type Tone = "error" | "warning" | "info" | "success";

const TONE_CLASSES: Record<Tone, string> = {
  error: "border-red-800 bg-red-950/60 text-red-200",
  warning: "border-amber-800 bg-amber-950/60 text-amber-200",
  info: "border-sky-800 bg-sky-950/60 text-sky-200",
  success: "border-emerald-800 bg-emerald-950/60 text-emerald-200",
};

export function Banner({
  tone = "info",
  title,
  children,
  onDismiss,
}: {
  tone?: Tone;
  title?: string;
  children?: ReactNode;
  onDismiss?: () => void;
}) {
  return (
    <div
      role={tone === "error" ? "alert" : "status"}
      className={`flex items-start gap-3 rounded-lg border px-4 py-3 text-sm ${TONE_CLASSES[tone]}`}
    >
      <div className="min-w-0 flex-1 space-y-1">
        {title ? <p className="font-semibold">{title}</p> : null}
        {children ? <div className="break-words">{children}</div> : null}
      </div>
      {onDismiss ? (
        <button
          type="button"
          onClick={onDismiss}
          aria-label="Dismiss"
          className="shrink-0 rounded px-1 text-lg leading-none opacity-70 hover:opacity-100"
        >
          ×
        </button>
      ) : null}
    </div>
  );
}

export function ErrorBanner({ error, onDismiss }: { error: string | null; onDismiss?: () => void }) {
  if (!error) return null;
  return (
    <Banner tone="error" title="Something went wrong" onDismiss={onDismiss}>
      {error}
    </Banner>
  );
}
