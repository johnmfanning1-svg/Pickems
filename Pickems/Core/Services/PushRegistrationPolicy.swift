import UserNotifications

/// Whether Pickems should ask the system for an APNs device token.
///
/// iOS permission alone does not deliver remote alerts — the app must also call
/// `UIApplication.registerForRemoteNotifications()` after authorization. Returning
/// users who already granted permission never hit the permission prompt, so this
/// gate is what keeps APNs registration alive across launches.
enum PushRegistrationPolicy {
    /// nonisolated: AppDelegate reads this from a `getNotificationSettings` callback
    /// that is not on the main actor under Swift 6.
    nonisolated static func shouldRegisterForRemoteNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
}
