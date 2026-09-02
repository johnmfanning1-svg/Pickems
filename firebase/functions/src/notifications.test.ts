import { describe, it, expect } from "vitest";
import {
  resolvePushDelivery,
  isUnregisteredFcmTokenError,
} from "./pushDelivery";

describe("resolvePushDelivery", () => {
  it("skips when the user has no FCM token", () => {
    expect(resolvePushDelivery({}, "week_scored")).toEqual({
      action: "skip",
      reason: "missing_token",
    });
    expect(resolvePushDelivery({ fcmToken: "" }, "chat_message")).toEqual({
      action: "skip",
      reason: "missing_token",
    });
    expect(resolvePushDelivery(undefined, "deadline_reminder")).toEqual({
      action: "skip",
      reason: "missing_token",
    });
  });

  it("sends when a token is present and prefs are missing (default on)", () => {
    expect(resolvePushDelivery({ fcmToken: "tok" }, "deadline_reminder")).toEqual({
      action: "send",
      token: "tok",
    });
    expect(resolvePushDelivery({ fcmToken: "tok" }, "week_scored")).toEqual({
      action: "send",
      token: "tok",
    });
  });

  it("honors deadline opt-outs without blocking other alert types", () => {
    const data = {
      fcmToken: "tok",
      notifyPickemsDeadlines: false,
      notifySelectionDeadlines: false,
    };
    expect(resolvePushDelivery(data, "deadline_reminder")).toEqual({
      action: "skip",
      reason: "pref_disabled",
    });
    expect(resolvePushDelivery(data, "selection_deadline_reminder")).toEqual({
      action: "skip",
      reason: "pref_disabled",
    });
    expect(resolvePushDelivery(data, "chat_message")).toEqual({
      action: "send",
      token: "tok",
    });
    expect(resolvePushDelivery(data, "game_final")).toEqual({
      action: "send",
      token: "tok",
    });
  });

  it("lets a league membership override skip a globally enabled alert", () => {
    expect(
      resolvePushDelivery(
        { fcmToken: "tok", notifyGameFinals: true },
        "game_final",
        { notifyGameFinals: false }
      )
    ).toEqual({ action: "skip", reason: "pref_disabled" });
  });

  it("skips game, chat, and scored-week pushes when those prefs are off", () => {
    expect(
      resolvePushDelivery(
        { fcmToken: "tok", notifyGameFinals: false },
        "game_final"
      )
    ).toEqual({ action: "skip", reason: "pref_disabled" });
    expect(
      resolvePushDelivery(
        { fcmToken: "tok", notifyChatMessages: false },
        "chat_message"
      )
    ).toEqual({ action: "skip", reason: "pref_disabled" });
    expect(
      resolvePushDelivery(
        { fcmToken: "tok", notifyWeekScored: false },
        "week_scored"
      )
    ).toEqual({ action: "skip", reason: "pref_disabled" });
  });
});

describe("isUnregisteredFcmTokenError", () => {
  it("matches admin SDK unregistered / invalid token codes", () => {
    expect(
      isUnregisteredFcmTokenError({
        code: "messaging/registration-token-not-registered",
      })
    ).toBe(true);
    expect(
      isUnregisteredFcmTokenError({
        errorInfo: { code: "messaging/invalid-registration-token" },
      })
    ).toBe(true);
  });

  it("does not treat payload or quota errors as stale tokens", () => {
    expect(isUnregisteredFcmTokenError({ code: "messaging/invalid-argument" })).toBe(
      false
    );
    expect(isUnregisteredFcmTokenError({ code: "messaging/internal-error" })).toBe(
      false
    );
    expect(isUnregisteredFcmTokenError(new Error("network"))).toBe(false);
    expect(isUnregisteredFcmTokenError(undefined)).toBe(false);
  });
});
