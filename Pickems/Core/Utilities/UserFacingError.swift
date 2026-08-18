import Foundation
import FirebaseFirestore

/// Maps raw Firebase / system errors into copy users should see — never
/// "Missing or insufficient permissions."
enum UserFacingError {
    /// User-visible message. Returns `nil` when the failure is expected noise
    /// (e.g. listing private picks before the deadline) and should not be shown.
    static func message(for error: Error, context: Context = .generic) -> String? {
        // SwiftUI `.task` / live-refresh restarts cancel in-flight ESPN calls. The
        // system copy is just "cancelled" — never show that as a Home banner.
        if isCancellation(error) { return nil }

        if isPermissionDenied(error) {
            switch context {
            case .privatePicks:
                // Listing everyone's picks is denied until lock/deadline — not a bug.
                return nil
            case .listener:
                return nil
            case .joinGroup:
                return "Couldn't open that league. Check the invite code and try again."
            case .write:
                return "You don't have permission to do that in this league."
            case .generic:
                return "Couldn't load that right now. Pull to refresh or try again in a moment."
            }
        }

        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return "Something went wrong. Please try again."
        }
        if looksLikeRawFirebasePermissionCopy(raw) {
            return "Couldn't load that right now. Pull to refresh or try again in a moment."
        }
        return raw
    }

    /// Assign into an optional error banner, clearing it when the error should be hidden.
    static func apply(_ error: Error, to target: inout String?, context: Context = .generic) {
        target = message(for: error, context: context)
    }

    enum Context {
        case generic
        /// Background snapshot listeners — don't flash banners for transient denies.
        case listener
        /// `getDocuments()` on picks before they are public.
        case privatePicks
        case joinGroup
        case write
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        let raw = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return raw == "cancelled" || raw == "canceled"
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return true
        }
        return looksLikeRawFirebasePermissionCopy(nsError.localizedDescription)
    }

    static func looksLikePermissionMessage(_ text: String) -> Bool {
        looksLikeRawFirebasePermissionCopy(text)
    }

    private static func looksLikeRawFirebasePermissionCopy(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("insufficient permissions")
            || lower.contains("permission denied")
            || lower.contains("missing or insufficient")
            || lower.contains("permission_denied")
    }
}
