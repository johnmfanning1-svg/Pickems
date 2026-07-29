import * as admin from "firebase-admin";

export type PushType =
  | "week_scored"
  | "deadline_reminder"
  | "deadline_locked"
  | "deadline_passed"
  | "game_final"
  | "took_the_lead"
  | "season_closed"
  | "chat_message";

export async function sendToUser(
  userId: string,
  title: string,
  body: string,
  type: PushType,
  extra: Record<string, string> = {}
): Promise<void> {
  const snap = await admin.firestore().collection("users").doc(userId).get();
  const token = snap.data()?.fcmToken as string | undefined;
  if (!token) return;

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
