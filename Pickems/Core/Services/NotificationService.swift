import Foundation
import FirebaseMessaging
import FirebaseFirestore
import UserNotifications
import UIKit

@MainActor
@Observable
final class NotificationService: NSObject {
    var isAuthorized = false
    /// Raw iOS authorization status for accurate Profile UI.
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var fcmToken: String?
    private var pendingUserId: String?
    private var didStart = false

    /// Do **not** touch `Messaging.messaging()` in `init`. AppState constructs this service
    /// during `PickemsApp.init`; Messaging before `FirebaseApp.configure()` aborts launch.
    override init() {
        super.init()
    }

    /// Call only after `FirebaseBootstrap.configureIfNeeded()` succeeds.
    func start() {
        guard !didStart else { return }
        guard FirebaseBootstrap.configureIfNeeded() else {
            AppLog.error(AppLog.notifications, "skip Messaging start — Firebase not configured")
            return
        }
        didStart = true
        Messaging.messaging().delegate = self
        AppLog.debug(AppLog.notifications, "Messaging delegate attached")
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        default:
            isAuthorized = false
        }
    }

    func requestPermissionIfNeeded() async {
        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .notDetermined:
            await requestPermission()
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
            UIApplication.shared.registerForRemoteNotifications()
        default:
            isAuthorized = false
        }
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            // Prefer the async API — the completion-handler form traps under MainActor
            // isolation when the system invokes the handler off-main (Swift 6).
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
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
            await refreshAuthorizationStatus()
        }
    }

    /// Opens iOS Settings → Pickems so the user can flip system notification permission.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
