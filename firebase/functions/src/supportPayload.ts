/**
 * Pure helpers for the public /support form. Kept free of firebase-admin so
 * unit tests can cover validation without initializing the Functions runtime.
 *
 * The inbox address itself never belongs in this file (or in any public HTML).
 */

export const SUPPORT_NAME_MAX = 120;
export const SUPPORT_EMAIL_MAX = 254;
export const SUPPORT_SUBJECT_MAX = 160;
export const SUPPORT_MESSAGE_MAX = 5000;
export const SUPPORT_RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
export const SUPPORT_RATE_LIMIT_MAX = 8;

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export interface SupportPayload {
  name: string;
  email: string;
  subject: string;
  message: string;
  honey: string;
}

export type SupportValidationError =
  | "invalid_email"
  | "empty_message"
  | "too_long";

export interface SupportRequestLike {
  method?: string;
  headers: Record<string, string | string[] | undefined>;
  body?: unknown;
  ip?: string;
}

export function headerValue(
  headers: SupportRequestLike["headers"],
  name: string
): string | undefined {
  const direct = headers[name] ?? headers[name.toLowerCase()];
  if (Array.isArray(direct)) return direct[0];
  if (typeof direct === "string") return direct;
  return undefined;
}

export function clientIp(req: SupportRequestLike): string {
  const forwarded = headerValue(req.headers, "x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first;
  }
  return req.ip?.trim() || "unknown";
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value) && !Buffer.isBuffer(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function field(record: Record<string, unknown>, ...keys: string[]): string {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string") return value;
    if (typeof value === "number" && Number.isFinite(value)) return String(value);
  }
  return "";
}

export function parseSupportBody(body: unknown, contentType = ""): SupportPayload {
  let record: Record<string, unknown> | null = asRecord(body);

  if (!record && typeof body === "string") {
    const trimmed = body.trim();
    if (!trimmed) {
      record = {};
    } else if (trimmed.startsWith("{") || contentType.includes("application/json")) {
      try {
        record = asRecord(JSON.parse(trimmed)) ?? {};
      } catch {
        record = {};
      }
    } else {
      record = Object.fromEntries(new URLSearchParams(trimmed));
    }
  }

  if (!record && contentType.includes("application/x-www-form-urlencoded") && typeof body === "string") {
    record = Object.fromEntries(new URLSearchParams(body));
  }

  const source = record ?? {};
  return {
    name: field(source, "name").trim(),
    email: field(source, "email").trim(),
    subject: field(source, "subject").trim(),
    message: field(source, "message").trim(),
    honey: field(source, "honey", "_honey").trim(),
  };
}

export function validateSupportPayload(
  payload: SupportPayload
): SupportValidationError | null {
  if (payload.name.length > SUPPORT_NAME_MAX) return "too_long";
  if (payload.email.length > SUPPORT_EMAIL_MAX) return "too_long";
  if (payload.subject.length > SUPPORT_SUBJECT_MAX) return "too_long";
  if (payload.message.length > SUPPORT_MESSAGE_MAX) return "too_long";
  if (!EMAIL_RE.test(payload.email)) return "invalid_email";
  if (!payload.message) return "empty_message";
  return null;
}

export function validationMessage(error: SupportValidationError): string {
  switch (error) {
    case "invalid_email":
      return "Enter a valid email so we can reply.";
    case "empty_message":
      return "Write a short message.";
    case "too_long":
      return "That message is too long.";
  }
}

export function mailSubject(payload: SupportPayload): string {
  return payload.subject ? `Pickems support: ${payload.subject}` : "Pickems support request";
}

export type MailBackend = "web3forms" | "formsubmit" | "none";

export function chooseMailBackend(web3Key: string | null, inbox: string | null): MailBackend {
  if (web3Key && web3Key.trim()) return "web3forms";
  if (inbox && inbox.trim()) return "formsubmit";
  return "none";
}

export function formSubmitUrl(inbox: string): string {
  return `https://formsubmit.co/ajax/${encodeURIComponent(inbox.trim())}`;
}

export function formSubmitJson(payload: SupportPayload): Record<string, string> {
  return {
    name: payload.name,
    email: payload.email,
    message: payload.message,
    _subject: mailSubject(payload),
    _template: "table",
    _captcha: "false",
  };
}

export function web3formsJson(accessKey: string, payload: SupportPayload): Record<string, string> {
  return {
    access_key: accessKey,
    subject: mailSubject(payload),
    from_name: payload.name || "Pickems support form",
    name: payload.name,
    email: payload.email,
    message: payload.message,
  };
}

const ALLOWED_REDIRECT_ORIGINS = new Set([
  "https://pickems-fb.web.app",
  "https://pickems-fb.firebaseapp.com",
]);

export function isLocalDevOrigin(origin: string): boolean {
  return /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(origin);
}

export function sentRedirectUrl(originHeader?: string, refererHeader?: string): string {
  const origin = (originHeader || "").trim().replace(/\/$/, "");
  if (ALLOWED_REDIRECT_ORIGINS.has(origin) || isLocalDevOrigin(origin)) {
    return `${origin}/support?sent=1`;
  }
  const referer = (refererHeader || "").trim();
  try {
    const url = new URL(referer);
    const refererOrigin = url.origin;
    if (ALLOWED_REDIRECT_ORIGINS.has(refererOrigin) || isLocalDevOrigin(refererOrigin)) {
      return `${refererOrigin}/support?sent=1`;
    }
  } catch {
    // ignore malformed referer
  }
  return "https://pickems-fb.web.app/support?sent=1";
}

export class SlidingWindowRateLimit {
  private readonly hits = new Map<string, number[]>();

  constructor(
    private readonly windowMs = SUPPORT_RATE_LIMIT_WINDOW_MS,
    private readonly max = SUPPORT_RATE_LIMIT_MAX,
    private readonly now: () => number = Date.now
  ) {}

  tooMany(ip: string): boolean {
    const t = this.now();
    const previous = (this.hits.get(ip) ?? []).filter((stamp) => t - stamp < this.windowMs);
    previous.push(t);
    this.hits.set(ip, previous);
    return previous.length > this.max;
  }
}
