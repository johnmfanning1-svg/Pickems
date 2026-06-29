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
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            isAuthorized = false
        }
    }

    func saveToken(for userId: String) async {
        pendingUserId = userId
        guard let token = fcmToken else { return }
        let db = Firestore.firestore()
        try? await db.user(userId).updateData([FirestoreField.fcmToken: token])
    }

    private func persistTokenIfNeeded() async {
        guard let userId = pendingUserId, let token = fcmToken else { return }
        let db = Firestore.firestore()
        try? await db.user(userId).updateData([FirestoreField.fcmToken: token])
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
