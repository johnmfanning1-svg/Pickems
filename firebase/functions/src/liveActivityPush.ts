import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import {
  isStaleLiveActivityTokenError,
  LIVE_ACTIVITY_FIELDS,
  liveActivityKey,
  planLiveActivityPushes,
  type LiveActivityPickSource,
} from "./liveActivityContent";
import { membersOnRoster, type MemberDoc, type PickDoc, type PickMode, type SlateGameDoc } from "./scoring";

/**
 * One update per viewer whose picked game changed. The payload is built from
 * that viewer's pick doc only. `dismiss` ends the activity after the week scores.
 */
export async function pushLiveActivityUpdates(input: {
  groupId: string;
  weekId: string;
  games: SlateGameDoc[];
  changedGameIds: ReadonlySet<string>;
  pickMode: PickMode;
  dismiss: boolean;
  nowMs: number;
  memberIds: string[];
  applyLatePenalty: boolean;
  latePickPenaltyWins: number;
  deadline: unknown;
}): Promise<void> {
  const db = getFirestore();
  const key = liveActivityKey(input.groupId, input.weekId);
  const subsSnap = await db.collection("users").where(LIVE_ACTIVITY_FIELDS.key, "==", key).get();
  if (subsSnap.empty) return;

  const subscriptions = subsSnap.docs.flatMap((doc) => {
    const data = doc.data();
    const fcmToken = text(data.fcmToken);
    const liveActivityToken = text(data[LIVE_ACTIVITY_FIELDS.token]);
    if (!fcmToken || !liveActivityToken) return [];
    return [{ userId: doc.id, fcmToken, liveActivityToken }];
  });
  if (subscriptions.length === 0) return;

  const groupRef = db.collection("groups").doc(input.groupId);
  const [membersSnap, picksSnap] = await Promise.all([
    groupRef.collection("members").get(),
    groupRef.collection("weeks").doc(input.weekId).collection("picks").get(),
  ]);
  const members = membersOnRoster(
    membersSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() } as MemberDoc)),
    input.memberIds
  ).map((member) => ({ id: member.id, displayName: member.displayName ?? "" }));

  const picksByUserId: Record<string, LiveActivityPickSource> = {};
  for (const doc of picksSnap.docs) {
    const data = doc.data() as PickDoc;
    picksByUserId[doc.id] = {
      picks: data.picks ?? {},
      confidenceGameId: data.confidenceGameId,
      submittedAt: data.submittedAt,
    };
  }

  const plans = planLiveActivityPushes({
    games: input.games,
    members,
    picksByUserId,
    subscriptions,
    changedGameIds: input.changedGameIds,
    pickMode: input.pickMode,
    applyLatePenalty: input.applyLatePenalty,
    latePickPenaltyWins: input.latePickPenaltyWins,
    deadline: input.deadline,
    dismiss: input.dismiss,
    nowMs: input.nowMs,
  });

  for (const plan of plans) {
    try {
      await getMessaging().send(plan.message);
      logger.info("live_activity", {
        groupId: input.groupId,
        weekId: input.weekId,
        userId: plan.userId,
        event: plan.event,
        picks: plan.pickCount,
      });
    } catch (err) {
      logger.error("live activity push failed", {
        groupId: input.groupId,
        weekId: input.weekId,
        userId: plan.userId,
        event: plan.event,
        code: codeOf(err),
      });
      if (!isStaleLiveActivityTokenError(err)) continue;
      try {
        await db.collection("users").doc(plan.userId).set(
          {
            [LIVE_ACTIVITY_FIELDS.token]: FieldValue.delete(),
            [LIVE_ACTIVITY_FIELDS.groupId]: FieldValue.delete(),
            [LIVE_ACTIVITY_FIELDS.weekId]: FieldValue.delete(),
            [LIVE_ACTIVITY_FIELDS.key]: FieldValue.delete(),
          },
          { merge: true }
        );
      } catch (clearErr) {
        logger.error("live activity token clear failed", {
          userId: plan.userId,
          code: codeOf(clearErr),
        });
      }
    }
  }
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function codeOf(err: unknown): string {
  if (!err || typeof err !== "object") return "";
  const record = err as { code?: unknown; errorInfo?: { code?: unknown } };
  if (typeof record.code === "string") return record.code;
  if (typeof record.errorInfo?.code === "string") return record.errorInfo.code;
  return "";
}
