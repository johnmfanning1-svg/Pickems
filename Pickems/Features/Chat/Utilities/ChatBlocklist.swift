import Foundation

/// Device-local moderation state: blocked authors and individually hidden messages.
///
/// Blocking is deliberately local. Apple's Guideline 1.2 requires that a blocked
/// user's content disappears for the person who blocked them; it does not require
/// a server-side relationship, and keeping it off Firestore means no new rules,
/// no extra reads, and no way for one member to censor a league for everyone else.
/// Keys are scoped by owner uid so a shared device doesn't leak one account's
/// blocklist into another's.
struct ChatBlocklist {
    private let ownerId: String
    private let defaults: UserDefaults

    init(ownerId: String, defaults: UserDefaults = .standard) {
        self.ownerId = ownerId
        self.defaults = defaults
    }

    private var blockedKey: String { "chat.blockedUserIds.\(ownerId)" }
    private var hiddenKey: String { "chat.hiddenMessageIds.\(ownerId)" }

    var blockedUserIds: Set<String> {
        Set(defaults.stringArray(forKey: blockedKey) ?? [])
    }

    /// Messages the owner reported or hid — removed from their feed immediately,
    /// without waiting for a moderator.
    var hiddenMessageIds: Set<String> {
        Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    }

    func isBlocked(_ userId: String) -> Bool {
        blockedUserIds.contains(userId)
    }

    @discardableResult
    func block(_ userId: String) -> Set<String> {
        guard userId != ownerId else { return blockedUserIds }
        var updated = blockedUserIds
        updated.insert(userId)
        defaults.set(Array(updated), forKey: blockedKey)
        return updated
    }

    @discardableResult
    func unblock(_ userId: String) -> Set<String> {
        var updated = blockedUserIds
        updated.remove(userId)
        defaults.set(Array(updated), forKey: blockedKey)
        return updated
    }

    @discardableResult
    func hide(messageId: String) -> Set<String> {
        var updated = hiddenMessageIds
        updated.insert(messageId)
        defaults.set(Array(updated), forKey: hiddenKey)
        return updated
    }
}
