import { shouldSendDeadlinePush, type PushPrefFields } from "./deadlinePushPrefs";

export type PushDeliveryDecision =
  | { action: "send"; token: string }
  | { action: "skip"; reason: "missing_token" | "pref_disabled" };

/** Decide whether a user doc can receive this push. Missing prefs default to on. */
export function resolvePushDelivery(
  data: ({ fcmToken?: unknown } & PushPrefFields) | undefined,
  type: string
): PushDeliveryDecision {
  const token = data?.fcmToken;
  if (typeof token !== "string" || token.length === 0) {
    return { action: "skip", reason: "missing_token" };
  }
  if (!shouldSendDeadlinePush(data, type)) {
    return { action: "skip", reason: "pref_disabled" };
  }
  return { action: "send", token };
}

export function isUnregisteredFcmTokenError(err: unknown): boolean {
  const code = fcmErrorCode(err);
  return (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token"
  );
}

function fcmErrorCode(err: unknown): string | undefined {
  if (!err || typeof err !== "object") return undefined;
  const rec = err as { code?: unknown; errorInfo?: { code?: unknown } };
  if (typeof rec.code === "string") return rec.code;
  if (typeof rec.errorInfo?.code === "string") return rec.errorInfo.code;
  return undefined;
}
