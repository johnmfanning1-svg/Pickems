import { Timestamp } from "firebase/firestore";

const dateTime = new Intl.DateTimeFormat(undefined, {
  year: "numeric",
  month: "short",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
});

export function toDate(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

export function formatTimestamp(value: unknown, fallback = "—"): string {
  const date = toDate(value);
  return date ? dateTime.format(date) : fallback;
}

export function formatRelative(value: unknown): string {
  const date = toDate(value);
  if (!date) return "—";
  const seconds = Math.round((Date.now() - date.getTime()) / 1000);
  const abs = Math.abs(seconds);
  if (abs < 60) return "just now";
  if (abs < 3600) return `${Math.round(abs / 60)}m ago`;
  if (abs < 86_400) return `${Math.round(abs / 3600)}h ago`;
  return `${Math.round(abs / 86_400)}d ago`;
}

/** `<input type="datetime-local">` wants a local-time string with no zone. */
export function toDateTimeLocalValue(value: unknown): string {
  const date = toDate(value);
  if (!date) return "";
  const pad = (n: number) => String(n).padStart(2, "0");
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}`
  );
}

/** Callables take ISO-8601; a blank input means "clear the deadline". */
export function fromDateTimeLocalValue(value: string): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

/** Matches `SlateGame.spreadLabel(for:)` in the iOS client. */
export function spreadLabel(spread: number, spreadTeamId: string, teamId: string): string {
  const sign = teamId === spreadTeamId ? "-" : "+";
  return `${sign}${Math.abs(spread).toFixed(1)}`;
}

/** The favourite always carries the minus, so the line reads the way it does in the app. */
export function favoriteSpreadLabel(spread: number): string {
  return `-${Math.abs(spread).toFixed(1)}`;
}

export function matchupLabel(away: string, home: string): string {
  return `${away} @ ${home}`;
}

export function record(wins: number | undefined, losses: number | undefined): string {
  return `${wins ?? 0}-${losses ?? 0}`;
}

export function truncate(value: string, max = 120): string {
  return value.length <= max ? value : `${value.slice(0, max - 1)}…`;
}
