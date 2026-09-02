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
    private var lastPersisted: (userId: String, token: String)?
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
        // Defer APNs registration off `App.init` — UIApplication is not ready yet.
        Task { await syncWithSystem() }
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

    /// Re-read iOS permission, register for APNs when allowed, and persist the FCM token.
    /// Safe to call on every foreground / session ready — returning users never see the
    /// permission prompt again, so this is the path that actually wires APNs to FCM.
    func syncWithSystem() async {
        await refreshAuthorizationStatus()
        guard PushRegistrationPolicy.shouldRegisterForRemoteNotifications(authorizationStatus) else {
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
        await refreshFCMTokenIfPossible()
    }

    func requestPermissionIfNeeded() async {
        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .notDetermined:
            await requestPermission()
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
            UIApplication.shared.registerForRemoteNotifications()
            await refreshFCMTokenIfPossible()
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
                await refreshFCMTokenIfPossible()
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
        await syncWithSystem()
        guard let token = fcmToken else {
            AppLog.debug(AppLog.notifications, "saveToken deferred — no FCM token yet", metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
            return
        }
        await persistToken(userId: userId, token: token)
    }

    /// Drop the in-memory user so a token refresh after sign-out cannot write the
    /// previous account's Firestore doc.
    func forgetPendingUser() {
        pendingUserId = nil
        lastPersisted = nil
    }

    func clearStoredToken(for userId: String) async {
        pendingUserId = nil
        lastPersisted = nil
        do {
            try await Firestore.firestore().user(userId).updateData([
                FirestoreField.fcmToken: FieldValue.delete()
            ])
            AppLog.debug(AppLog.notifications, "FCM token cleared", metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
        } catch {
            AppLog.error(AppLog.notifications, "FCM token clear failed", error: error, metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
        }
    }

    private func persistTokenIfNeeded() async {
        guard let userId = pendingUserId, let token = fcmToken else { return }
        await persistToken(userId: userId, token: token)
    }

    private func persistToken(userId: String, token: String) async {
        if lastPersisted?.userId == userId, lastPersisted?.token == token {
            return
        }
        let db = Firestore.firestore()
        do {
            // Merge so a missing user doc (or a race with profile create) still stores the token.
            try await db.user(userId).setData([FirestoreField.fcmToken: token], merge: true)
            lastPersisted = (userId, token)
            AppLog.debug(AppLog.notifications, "FCM token saved", metadata: [
                "uid": AppEvents.shortUID(userId),
                "token_len": "\(token.count)",
            ])
            AppEvents.track(.notificationsTokenSaved, metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
        } catch {
            AppEvents.failure(.notificationsTokenSaveFailed, error: error, metadata: [
                "uid": AppEvents.shortUID(userId),
            ], recordNonFatal: false)
        }
    }

    /// `Messaging.token()` throws if APNs has not arrived yet — that is expected on
    /// the first launch after permission. The MessagingDelegate retry covers it.
    private func refreshFCMTokenIfPossible() async {
        do {
            let token = try await Messaging.messaging().token()
            fcmToken = token
            await persistTokenIfNeeded()
        } catch {
            AppLog.debug(AppLog.notifications, "FCM token fetch pending APNs", metadata: [
                "error": AppLog.describe(error),
            ])
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
