import * as admin from "firebase-admin";

export type PushType =
  | "week_scored"
  | "deadline_reminder"
  | "deadline_locked"
  | "deadline_passed"
  | "set_selection_deadline"
  | "selection_deadline_passed"
  | "selection_deadline_reminder"
  | "pickems_open"
  | "game_final"
  | "took_the_lead"
  | "season_closed"
  | "chat_message";

const SELECTION_DEADLINE_TYPES: PushType[] = [
  "set_selection_deadline",
  "selection_deadline_passed",
  "selection_deadline_reminder",
];

const PICKEMS_DEADLINE_TYPES: PushType[] = [
  "deadline_reminder",
  "deadline_locked",
  "deadline_passed",
  "pickems_open",
];

/** Missing prefs default to on so existing users keep receiving deadline alerts. */
export function shouldSendDeadlinePush(
  data: admin.firestore.DocumentData | undefined,
  type: PushType
): boolean {
  if (SELECTION_DEADLINE_TYPES.includes(type)) {
    return data?.notifySelectionDeadlines !== false;
  }
  if (PICKEMS_DEADLINE_TYPES.includes(type)) {
    return data?.notifyPickemsDeadlines !== false;
  }
  return true;
}

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
