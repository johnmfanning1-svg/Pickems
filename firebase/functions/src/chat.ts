import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendToUsers } from "./notifications";

/** Lazy — `admin.initializeApp()` runs in index.ts after this module is loaded. */
function db(): admin.firestore.Firestore {
  return admin.firestore();
}

/** Push bodies stay short enough to read on a lock screen. */
const NOTIFICATION_BODY_LIMIT = 120;

/**
 * Reports needed before a message is hidden from everyone. Mirrors
 * `ChatService.autoHideReportThreshold` on the client.
 */
const AUTO_HIDE_REPORT_THRESHOLD = 3;

function truncate(text: string, limit: number): string {
  const collapsed = text.replace(/\s+/g, " ").trim();
  return collapsed.length <= limit ? collapsed : `${collapsed.slice(0, limit - 1)}…`;
}

/**
 * Fan a new chat message out to the rest of the league.
 *
 * Recipients are `memberIds` minus the author minus anyone who set `chatMuted`
 * on their member doc. `sendToUsers` already swallows per-token failures, so one
 * stale FCM token cannot block the rest of the group.
 */
export const onMessageCreated = onDocumentCreated(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    if (message.isDeleted === true) return;

    const groupId = event.params.groupId;
    const messageId = event.params.messageId;
    const authorId = message.userId as string | undefined;
    const text = ((message.text as string | undefined) ?? "").trim();
    if (!authorId || text.length === 0) return;

    const [groupSnap, membersSnap] = await Promise.all([
      db().collection("groups").doc(groupId).get(),
      db().collection("groups").doc(groupId).collection("members").get(),
    ]);

    const group = groupSnap.data();
    if (!group) {
      logger.warn("chat message for missing group", { groupId, messageId });
      return;
    }

    const mutedIds = new Set(
      membersSnap.docs.filter((doc) => doc.data()?.chatMuted === true).map((doc) => doc.id)
    );
    const memberIds = (group.memberIds as string[] | undefined) ?? [];
    const recipients = memberIds.filter((id) => id !== authorId && !mutedIds.has(id));
    if (recipients.length === 0) return;

    const displayName = (message.displayName as string | undefined) ?? "Someone";
    const weekId = message.weekId as string | undefined;
    const extra: Record<string, string> = { groupId, messageId };
    if (weekId) extra.weekId = weekId;

    await sendToUsers(
      recipients,
      (group.name as string | undefined) ?? "Pickems",
      `${displayName}: ${truncate(text, NOTIFICATION_BODY_LIMIT)}`,
      "chat_message",
      extra
    );
  }
);

/**
 * Move the moderation counter a client is never allowed to touch.
 *
 * Rules pin `reportCount` to `0` on create and leave it out of every update
 * allow-list, so this trigger is the only writer. The transaction makes the
 * count and the auto-hide decision atomic — two simultaneous reports on the
 * third strike would otherwise both read the pre-increment value and neither
 * would hide the message.
 */
export const onReportCreated = onDocumentCreated(
  "groups/{groupId}/messages/{messageId}/reports/{reporterUid}",
  async (event) => {
    const groupId = event.params.groupId;
    const messageId = event.params.messageId;
    const messageRef = db()
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .doc(messageId);

    const outcome = await db().runTransaction(async (tx) => {
      const snap = await tx.get(messageRef);
      if (!snap.exists) return { hidden: false, count: 0, missing: true };

      const nextCount = ((snap.data()?.reportCount as number | undefined) ?? 0) + 1;
      const shouldHide = nextCount >= AUTO_HIDE_REPORT_THRESHOLD;
      const update: Record<string, unknown> = {
        reportCount: admin.firestore.FieldValue.increment(1),
      };
      if (shouldHide && snap.data()?.isDeleted !== true) {
        update.isDeleted = true;
      }
      tx.update(messageRef, update);
      return { hidden: shouldHide, count: nextCount, missing: false };
    });

    if (outcome.missing) {
      logger.warn("report for missing message", { groupId, messageId });
      return;
    }

    if (outcome.hidden) {
      logger.warn("chat message auto-hidden by reports", {
        groupId,
        messageId,
        reportCount: outcome.count,
      });
    }
  }
);
