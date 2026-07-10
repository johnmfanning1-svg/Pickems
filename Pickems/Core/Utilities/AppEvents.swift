import Foundation

/// Structured product/debug events. Always lands in OSLog; also breadcrumbs Crashlytics when linked.
enum AppEvent: String, CaseIterable {
    // App / session
    case appLaunch = "app.launch"
    case sessionBootstrapStarted = "session.bootstrap_started"
    case sessionBootstrapReady = "session.bootstrap_ready"
    case sessionBootstrapSkipped = "session.bootstrap_skipped"
    case rootDestinationChanged = "root.destination_changed"

    // Auth
    case authStateChanged = "auth.state_changed"
    case authSignInStarted = "auth.sign_in_started"
    case authSignInSucceeded = "auth.sign_in_succeeded"
    case authSignInFailed = "auth.sign_in_failed"
    case authSignUpStarted = "auth.sign_up_started"
    case authSignUpSucceeded = "auth.sign_up_succeeded"
    case authSignUpFailed = "auth.sign_up_failed"
    case authAppleStarted = "auth.apple_started"
    case authAppleSucceeded = "auth.apple_succeeded"
    case authAppleFailed = "auth.apple_failed"
    case authSignOut = "auth.sign_out"
    case authProfileLoaded = "auth.profile_loaded"
    case authProfileFallback = "auth.profile_fallback"
    case authProfileSyncFailed = "auth.profile_sync_failed"
    case authPasswordResetStarted = "auth.password_reset_started"
    case authPasswordResetSucceeded = "auth.password_reset_succeeded"
    case authPasswordResetFailed = "auth.password_reset_failed"
    case authEpochStaleIgnored = "auth.epoch_stale_ignored"

    // Onboarding / leagues
    case onboardingMarkedComplete = "onboarding.marked_complete"
    case onboardingJoinStarted = "onboarding.join_started"
    case onboardingJoinSucceeded = "onboarding.join_succeeded"
    case onboardingJoinFailed = "onboarding.join_failed"
    case onboardingCreateStarted = "onboarding.create_started"
    case onboardingCreateSucceeded = "onboarding.create_succeeded"
    case onboardingCreateFailed = "onboarding.create_failed"
    case favoriteTeamPromptPresented = "favorite_team.prompt_presented"
    case favoriteTeamSelected = "favorite_team.selected"
    case favoriteTeamCleared = "favorite_team.cleared"
    case favoriteTeamFailed = "favorite_team.failed"

    // Data
    case groupsListenerError = "groups.listener_error"
    case groupsDecodeDropped = "groups.decode_dropped"
    case weekListenerError = "week.listener_error"
    case picksListenerError = "picks.listener_error"
    case notificationsPermission = "notifications.permission"
    case notificationsTokenSaveFailed = "notifications.token_save_failed"
}

enum AppEvents {
    #if DEBUG
    private(set) static var recent: [(date: Date, name: String, metadata: [String: String])] = []
    private static let recentLimit = 100
    #endif

    static func track(_ event: AppEvent, metadata: [String: String] = [:]) {
        let safe = Self.redact(metadata)
        AppLog.info(AppLog.events, event.rawValue, metadata: safe)
        CrashReport.breadcrumb(event.rawValue, metadata: safe)
        #if DEBUG
        recent.insert((Date(), event.rawValue, safe), at: 0)
        if recent.count > recentLimit {
            recent = Array(recent.prefix(recentLimit))
        }
        #endif
    }

    static func failure(
        _ event: AppEvent,
        error: Error,
        metadata: [String: String] = [:],
        recordNonFatal: Bool = true
    ) {
        var safe = Self.redact(metadata)
        safe["error"] = AppLog.describe(error)
        AppLog.error(AppLog.events, event.rawValue, error: error, metadata: safe)
        CrashReport.breadcrumb(event.rawValue, metadata: safe)
        if recordNonFatal {
            CrashReport.record(error, code: event.rawValue, metadata: safe)
        }
        #if DEBUG
        recent.insert((Date(), "FAIL \(event.rawValue)", safe), at: 0)
        if recent.count > recentLimit {
            recent = Array(recent.prefix(recentLimit))
        }
        #endif
    }

    /// Never log emails, passwords, or raw tokens.
    static func redact(_ metadata: [String: String]) -> [String: String] {
        let blocked: Set<String> = [
            "email", "password", "token", "idToken", "fcmToken", "authorization",
        ]
        return metadata.reduce(into: [:]) { result, pair in
            if blocked.contains(pair.key) {
                result[pair.key] = "<redacted>"
            } else {
                result[pair.key] = pair.value
            }
        }
    }

    static func shortUID(_ uid: String?) -> String {
        guard let uid, !uid.isEmpty else { return "nil" }
        return String(uid.prefix(8))
    }
}
