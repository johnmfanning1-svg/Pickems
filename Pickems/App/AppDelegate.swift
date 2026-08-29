import UIKit
import UserNotifications

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
        return true
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
