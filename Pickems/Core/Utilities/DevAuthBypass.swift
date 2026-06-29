#if DEBUG
import Foundation

/// Temporary bypass for local feature testing. Set `isEnabled = true` to skip Sign in with Apple.
enum DevAuthBypass {
    static let isEnabled = false

    static let displayName = "Dev Tester"
    static let avatarColorHex = "#DC2626"
}
#endif
