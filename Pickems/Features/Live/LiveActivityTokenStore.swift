import FirebaseFirestore
import Foundation

/// The viewer's ActivityKit push token, on fields their own user doc can already write.
enum LiveActivityTokenStore {
    static func save(userId: String, token: String, groupId: String, weekId: String) async {
        guard !userId.isEmpty, !token.isEmpty, !groupId.isEmpty, !weekId.isEmpty else { return }
        do {
            try await Firestore.firestore().user(userId).setData([
                FirestoreField.liveActivityToken: token,
                FirestoreField.liveActivityGroupId: groupId,
                FirestoreField.liveActivityWeekId: weekId,
                FirestoreField.liveActivityKey: LiveActivitySchema.activityKey(groupId: groupId, weekId: weekId),
            ], merge: true)
            AppLog.debug(AppLog.notifications, "Live Activity token saved", metadata: [
                "uid": AppEvents.shortUID(userId),
                "token_len": "\(token.count)",
            ])
        } catch {
            AppLog.error(AppLog.notifications, "Live Activity token save failed", error: error, metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
        }
    }

    static func clear(userId: String) async {
        guard !userId.isEmpty else { return }
        do {
            try await Firestore.firestore().user(userId).setData([
                FirestoreField.liveActivityToken: FieldValue.delete(),
                FirestoreField.liveActivityGroupId: FieldValue.delete(),
                FirestoreField.liveActivityWeekId: FieldValue.delete(),
                FirestoreField.liveActivityKey: FieldValue.delete(),
            ], merge: true)
        } catch {
            AppLog.error(AppLog.notifications, "Live Activity token clear failed", error: error, metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
        }
    }
}
