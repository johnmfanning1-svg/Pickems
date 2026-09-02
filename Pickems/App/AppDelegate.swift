import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// UIKit launch hook. Firebase *must* be configured here before Messaging's App Delegate
/// Proxy runs other swizzled callbacks. Keep notification delegate methods on the
/// completion-handler APIs — the `async` variants trap under Swift 6 / MainActor isolation
/// when UserNotifications invokes them off the main actor (instant TestFlight launch kill).
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Default portrait so tabs stay upright. Landscape is allowed only while the
    /// expanded League Pickems chart is presented.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    private(set) var pendingDeepLink: DeepLinkAction?
    var onDeepLink: ((DeepLinkAction) -> Void)?

    func setDeepLinkHandler(_ handler: @escaping (DeepLinkAction) -> Void) {
        onDeepLink = handler
        deliverPendingDeepLinkIfNeeded()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // First line on purpose: swizzled Messaging / Analytics code may run around launch.
        _ = FirebaseBootstrap.configureIfNeeded()
        UNUserNotificationCenter.current().delegate = self
        // Completion-handler API — the async `notificationSettings()` hop can trap under
        // Swift 6 if this callback is invoked off-main. Returning users already granted
        // permission, so this is the launch path that actually registers for APNs.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard PushRegistrationPolicy.shouldRegisterForRemoteNotifications(settings.authorizationStatus) else {
                    return
                }
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    /// SwiftUI's `UIApplicationDelegateAdaptor` does not always receive Firebase's
    /// swizzled APNs callback, so assign the token explicitly.
    nonisolated func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            guard FirebaseApp.app() != nil else { return }
            Messaging.messaging().apnsToken = deviceToken
            AppLog.info(AppLog.notifications, "APNs token received", metadata: [
                "bytes": "\(deviceToken.count)",
            ])
        }
    }

    nonisolated func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            AppEvents.failure(.notificationsAPNsFailed, error: error, recordNonFatal: false)
        }
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    private func deliverPendingDeepLinkIfNeeded() {
        guard let action = pendingDeepLink, let onDeepLink else { return }
        pendingDeepLink = nil
        onDeepLink(action)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let action = DeepLinkRouter.parseNotification(userInfo: userInfo)
        // Complete immediately — do not hop actors before calling the handler (Swift 6 trap).
        completionHandler()
        guard let action else { return }
        Task { @MainActor in
            if let onDeepLink {
                onDeepLink(action)
            } else {
                pendingDeepLink = action
            }
        }
    }
}
