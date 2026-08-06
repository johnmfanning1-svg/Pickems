#if DEBUG
import Foundation

/// Dev-only admin access. Remove this file (and admin UI) before App Store submission.
/// Fill locally for DEBUG admin; never commit real credentials.
enum DevAdminConfig {
    /// Password typed in the Admin sheet (local gate only).
    static let gatePassword = ""

    /// Defaults for Firebase Email/Password — must match the user in Firebase Console exactly.
    static let defaultEmail = ""
    static let defaultFirebasePassword = ""

    static let displayName = "Admin"
}
#endif
