import Foundation

/// A single group chat message: `groups/{groupId}/messages/{messageId}`.
///
/// Field names and constraints mirror `firestore.rules` exactly — `text` is
/// 1...500 characters, `isDeleted` and `reportCount` are pinned on create, and
/// `createdAt` must be the server clock so thread order cannot be forged.
struct ChatMessage: Codable, Identifiable, Equatable {
    /// Maximum characters accepted by the rules; enforced client-side too so the
    /// composer fails visibly instead of bouncing off a permission error.
    static let maxTextLength = 500

    var id: String
    var groupId: String
    /// Nil means league-wide rather than tied to a single week.
    var weekId: String?
    var userId: String
    var displayName: String
    var avatarColorHex: String
    var text: String
    /// Nil only while a locally-written message waits for the server to resolve
    /// `FieldValue.serverTimestamp()`. Reads from the server always have a value.
    var createdAt: Date?
    var editedAt: Date?
    /// Soft delete keeps thread order intact and preserves the moderation trail.
    var isDeleted: Bool
    /// emoji -> [uid]. v1 never writes this; the rules already permit it.
    var reactions: [String: [String]]?
    /// Incremented only by the `onReportCreated` Cloud Function.
    var reportCount: Int

    /// Ordering key that keeps an unconfirmed local message at the bottom of the thread.
    var sortDate: Date { createdAt ?? Date() }

    /// True between the optimistic local write and the server acknowledgement.
    var isPending: Bool { createdAt == nil }

    var initials: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(2)).uppercased()
    }
}

/// Reasons offered when reporting a message. Raw values land in the report doc
/// and are what the moderation queue in the admin portal groups by.
enum ChatReportReason: String, CaseIterable, Identifiable {
    case harassment
    case hateSpeech = "hate_speech"
    case sexualContent = "sexual_content"
    case spam
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment: return "Harassment or bullying"
        case .hateSpeech: return "Hate speech"
        case .sexualContent: return "Sexual or graphic content"
        case .spam: return "Spam or scam"
        case .other: return "Something else"
        }
    }
}
