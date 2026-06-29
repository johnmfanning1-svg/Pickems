#if DEBUG
import Foundation

/// Dev-only admin access. Remove this file (and admin UI) before App Store submission.
enum DevAdminConfig {
    /// Password typed in the Admin sheet (local gate only).
    static let gatePassword = "pickems-admin"

    /// Defaults for Firebase Email/Password — must match the user in Firebase Console exactly.
    static let defaultEmail = "pickems.dev.admin@gmail.com"
    static let defaultFirebasePassword = "PickemsDev1"

    static let displayName = "Admin"
}
#endif
