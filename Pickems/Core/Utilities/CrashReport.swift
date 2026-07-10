import Foundation

#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

/// Non-fatal / breadcrumb reporting. Uses Crashlytics when the SDK is linked; always mirrors to OSLog.
enum CrashReport {
    static func configureAfterFirebase() {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        AppLog.info(AppLog.session, "Crashlytics collection enabled")
        #else
        AppLog.debug(AppLog.session, "Crashlytics not linked — OSLog only")
        #endif
    }

    static func setUserID(_ userId: String?) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setUserID(userId)
        #endif
        if let userId {
            AppLog.debug(AppLog.session, "CrashReport user set", metadata: [
                "uid": AppEvents.shortUID(userId),
            ])
        }
    }

    static func setValue(_ value: String?, forKey key: String) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
        #endif
    }

    static func breadcrumb(_ message: String, metadata: [String: String] = [:]) {
        let line: String
        if metadata.isEmpty {
            line = message
        } else {
            let pairs = metadata.keys.sorted().map { "\($0)=\(metadata[$0] ?? "")" }
            line = "\(message) {\(pairs.joined(separator: ", "))}"
        }
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().log(line)
        #endif
        AppLog.debug(AppLog.session, "breadcrumb: \(line)")
    }

    static func record(_ error: Error, code: String, metadata: [String: String] = [:]) {
        var userInfo: [String: Any] = ["pickems_code": code]
        for (key, value) in metadata {
            userInfo[key] = value
        }
        let nsError = error as NSError
        let wrapped = NSError(
            domain: "Pickems.\(nsError.domain)",
            code: nsError.code,
            userInfo: userInfo.merging(nsError.userInfo) { _, new in new }
                .merging([NSLocalizedDescriptionKey: error.localizedDescription]) { _, new in new }
        )
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().record(error: wrapped)
        #endif
        AppLog.error(AppLog.session, "nonfatal recorded", error: error, metadata: metadata.merging([
            "code": code,
        ]) { _, new in new })
    }
}
