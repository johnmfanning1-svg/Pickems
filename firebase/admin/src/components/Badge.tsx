import type { ReactNode } from "react";
import type { WeekStatus } from "@/lib/types";

type Tone = "neutral" | "info" | "success" | "warning" | "danger";

const TONE_CLASSES: Record<Tone, string> = {
  neutral: "bg-ink-600 text-slate-300 ring-slate-600",
  info: "bg-sky-950 text-sky-300 ring-sky-800",
  success: "bg-emerald-950 text-emerald-300 ring-emerald-800",
  warning: "bg-amber-950 text-amber-300 ring-amber-800",
  danger: "bg-red-950 text-red-300 ring-red-800",
};

export function Badge({ tone = "neutral", children }: { tone?: Tone; children: ReactNode }) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${TONE_CLASSES[tone]}`}
    >
      {children}
    </span>
  );
}

const WEEK_STATUS_TONE: Record<WeekStatus, Tone> = {
  selection: "info",
  picking: "warning",
  locked: "neutral",
  scored: "success",
};

export function WeekStatusBadge({ status }: { status?: string }) {
  if (!status) return <Badge tone="danger">no status</Badge>;
  const tone = WEEK_STATUS_TONE[status as WeekStatus] ?? "danger";
  return <Badge tone={tone}>{status}</Badge>;
}
