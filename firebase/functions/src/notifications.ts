import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { shouldSendDeadlinePush, type DeadlinePushType } from "./deadlinePushPrefs";
import { isUnregisteredFcmTokenError, resolvePushDelivery } from "./pushDelivery";

export type PushType = DeadlinePushType;
export { shouldSendDeadlinePush, resolvePushDelivery, isUnregisteredFcmTokenError };

export async function sendToUser(
  userId: string,
  title: string,
  body: string,
  type: PushType,
  extra: Record<string, string> = {}
): Promise<void> {
  try {
    const snap = await admin.firestore().collection("users").doc(userId).get();
    const decision = resolvePushDelivery(snap.data(), type);
    if (decision.action === "skip") {
      logger.info("push skipped", { userId, type, reason: decision.reason });
      return;
    }

    await admin.messaging().send({
      token: decision.token,
      notification: { title, body },
      data: { type, ...extra },
      apns: {
        headers: {
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });
  } catch (err) {
    if (isUnregisteredFcmTokenError(err)) {
      logger.warn("clearing stale FCM token", { userId, type });
      try {
        await admin.firestore().collection("users").doc(userId).update({
          fcmToken: admin.firestore.FieldValue.delete(),
        });
      } catch (clearErr) {
        logger.error("failed to clear stale FCM token", {
          userId,
          error: String(clearErr),
        });
      }
      return;
    }
    logger.error("push send failed", { userId, type, error: String(err) });
  }
}

export async function sendToUsers(
  userIds: string[],
  title: string,
  body: string,
  type: PushType,
  extra: Record<string, string> = {}
): Promise<void> {
  await Promise.all(
    userIds.map((id) => sendToUser(id, title, body, type, extra).catch(() => undefined))
  );
}
