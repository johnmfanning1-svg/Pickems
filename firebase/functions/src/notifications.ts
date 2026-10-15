import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { shouldSendDeadlinePush, type DeadlinePushType, type MemberPushPrefFields } from "./deadlinePushPrefs";
import { buildPushMessage, type PushPresentation } from "./pushAlert";
import { isUnregisteredFcmTokenError, resolvePushDelivery } from "./pushDelivery";

export type PushType = DeadlinePushType;
export { shouldSendDeadlinePush, resolvePushDelivery, isUnregisteredFcmTokenError };

export async function sendToUser(
  userId: string,
  title: string,
  body: string,
  type: PushType,
  extra: Record<string, string> = {},
  member?: MemberPushPrefFields,
  presentation?: PushPresentation
): Promise<boolean> {
  try {
    const snap = await getFirestore().collection("users").doc(userId).get();
    let memberPrefs = member;
    if (memberPrefs === undefined && extra.groupId) {
      const memberSnap = await getFirestore()
        .collection("groups")
        .doc(extra.groupId)
        .collection("members")
        .doc(userId)
        .get();
      memberPrefs = memberSnap.data() as MemberPushPrefFields | undefined;
    }
    const decision = resolvePushDelivery(snap.data(), type, memberPrefs);
    if (decision.action === "skip") {
      logger.info("push skipped", { userId, type, reason: decision.reason, groupId: extra.groupId });
      return true;
    }

    await getMessaging().send(
      buildPushMessage({
        token: decision.token,
        title,
        body,
        data: { ...extra, type: presentation?.payloadType ?? type },
        presentation,
      })
    );
    return true;
  } catch (err) {
    if (isUnregisteredFcmTokenError(err)) {
      logger.warn("clearing stale FCM token", { userId, type });
      try {
        await getFirestore().collection("users").doc(userId).update({
          fcmToken: FieldValue.delete(),
        });
      } catch (clearErr) {
        logger.error("failed to clear stale FCM token", {
          userId,
          error: String(clearErr),
        });
      }
      return true;
    }
    logger.error("push send failed", { userId, type, error: String(err) });
    return false;
  }
}

export async function sendToUsers(
  userIds: string[],
  title: string,
  body: string,
  type: PushType,
  extra: Record<string, string> = {}
): Promise<void> {
  let membersById = new Map<string, MemberPushPrefFields>();
  if (extra.groupId) {
    const membersSnap = await getFirestore()
      .collection("groups")
      .doc(extra.groupId)
      .collection("members")
      .get();
    membersById = new Map(
      membersSnap.docs.map((doc) => [doc.id, doc.data() as MemberPushPrefFields])
    );
  }
  await Promise.all(
    userIds.map((id) =>
      sendToUser(
        id,
        title,
        body,
        type,
        extra,
        extra.groupId ? (membersById.get(id) ?? {}) : undefined
      ).catch(() => undefined)
    )
  );
}
