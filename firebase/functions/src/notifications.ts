import * as admin from "firebase-admin";
import { shouldSendDeadlinePush, type DeadlinePushType } from "./deadlinePushPrefs";

export type PushType = DeadlinePushType;
export { shouldSendDeadlinePush };

export async function sendToUser(
  userId: string,
  title: string,
  body: string,
  type: PushType,
  extra: Record<string, string> = {}
): Promise<void> {
  const snap = await admin.firestore().collection("users").doc(userId).get();
  const data = snap.data();
  const token = data?.fcmToken as string | undefined;
  if (!token) return;
  if (!shouldSendDeadlinePush(data, type)) return;

  await admin.messaging().send({
    token,
    notification: { title, body },
    data: { type, ...extra },
    apns: {
      payload: {
        aps: {
          sound: "default",
          "mutable-content": 1,
        },
      },
    },
  });
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
