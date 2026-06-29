import Foundation

struct XAuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scope: String?
    let xUserId: String?
    let xUsername: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

enum XAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case invalidCallback
    case tokenExchangeFailed
    case notConnected
    case postFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "X integration is not configured. Add your Client ID in AppConfig."
        case .cancelled:
            return "X sign-in was cancelled."
        case .invalidCallback:
            return "Invalid OAuth callback from X."
        case .tokenExchangeFailed:
            return "Could not complete X sign-in."
        case .notConnected:
            return "Connect your X account in Settings to post directly."
        case .postFailed(let message):
            return "Failed to post to X: \(message)"
        }
    }
}
