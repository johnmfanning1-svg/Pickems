import FirebaseCore
import FirebaseFirestore

enum FirebaseBootstrap {
    private static var didConfigure = false

    /// Must run before any `Auth.auth()`, `Firestore.firestore()`, or `Messaging.messaging()` call.
    /// Safe to call from both `AppDelegate.didFinishLaunching` and `PickemsApp.init` —
    /// Messaging's App Delegate Proxy can touch Firebase during launch, so configure early
    /// and idempotently in both places.
    @discardableResult
    static func configureIfNeeded() -> Bool {
        if didConfigure {
            return FirebaseApp.app() != nil
        }

        if FirebaseApp.app() == nil {
            // Prefer the bundled plist; never crash the process if it's missing — surface a
            // recoverable boot failure instead of an uncaught FIR exception on TestFlight.
            if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") == nil {
                AppLog.error(
                    AppLog.session,
                    "GoogleService-Info.plist missing from app bundle — Firebase cannot start"
                )
                didConfigure = true
                return false
            }
            FirebaseApp.configure()
        }

        guard FirebaseApp.app() != nil else {
            AppLog.error(AppLog.session, "FirebaseApp.configure() produced no default app")
            didConfigure = true
            return false
        }

        // Assign a fresh settings object before any Firestore use. Mutating after first use
        // throws FIRIllegalStateException and kills launch.
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: 100 * 1024 * 1024 as NSNumber
        )
        Firestore.firestore().settings = settings

        CrashReport.configureAfterFirebase()
        AppEvents.track(.appLaunch)
        didConfigure = true
        return true
    }
}
