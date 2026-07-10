import Foundation
import FirebaseMessaging
import FirebaseFirestore
import UserNotifications
import UIKit

@MainActor
@Observable
final class NotificationService: NSObject {
    var isAuthorized = false
    var fcmToken: String?
    private var pendingUserId: String?

    override init() {
        super.init()
        Messaging.messaging().delegate = self
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            AppEvents.track(.notificationsPermission, metadata: [
                "granted": granted ? "true" : "false",
            ])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            isAuthorized = false
            AppLog.error(AppLog.notifications, "permission request failed", error: error)
            AppEvents.track(.notificationsPermission, metadata: [
                "granted": "false",
                "error": AppLog.describe(error),
            ])
        }
    }

    func saveToken(for userId: String) async {
        pendingUserId = userId
        guard let token = fcmToken else {
            AppLog.debug(AppLog.notifications, "saveToken deferred — no FCM token yet", metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
            return
        }
        await persistToken(userId: userId, token: token)
    }

    private func persistTokenIfNeeded() async {
        guard let userId = pendingUserId, let token = fcmToken else { return }
        await persistToken(userId: userId, token: token)
    }

    private func persistToken(userId: String, token: String) async {
        let db = Firestore.firestore()
        do {
            try await db.user(userId).updateData([FirestoreField.fcmToken: token])
            AppLog.debug(AppLog.notifications, "FCM token saved", metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
        } catch {
            AppEvents.failure(.notificationsTokenSaveFailed, error: error, metadata: [
                "uid": AppEvents.shortUID(userId),
            ], recordNonFatal: false)
        }
    }
}

extension NotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.fcmToken = fcmToken
            await self.persistTokenIfNeeded()
        }
    }
}
