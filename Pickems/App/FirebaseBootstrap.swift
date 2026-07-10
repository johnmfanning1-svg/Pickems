import FirebaseCore
import FirebaseFirestore

enum FirebaseBootstrap {
    private static var didConfigure = false

    /// Must run before any `Auth.auth()`, `Firestore.firestore()`, or `Messaging.messaging()` call.
    static func configureIfNeeded() {
        guard !didConfigure else { return }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        Firestore.firestore().settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: 100 * 1024 * 1024 as NSNumber
        )
        CrashReport.configureAfterFirebase()
        AppEvents.track(.appLaunch)
        didConfigure = true
    }
}
