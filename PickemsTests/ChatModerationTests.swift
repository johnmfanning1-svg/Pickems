import Foundation
import Testing
@testable import Pickems

struct ChatModerationTests {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "chat.tests.\(name)")!
        defaults.removePersistentDomain(forName: "chat.tests.\(name)")
        return defaults
    }

    @Test func blockingPersistsAndIsReversible() {
        let defaults = freshDefaults(#function)
        let blocklist = ChatBlocklist(ownerId: "owner", defaults: defaults)

        #expect(blocklist.blockedUserIds.isEmpty)
        blocklist.block("loudmouth")
        #expect(blocklist.isBlocked("loudmouth"))

        // A fresh instance reads the same store — the block survives a relaunch.
        #expect(ChatBlocklist(ownerId: "owner", defaults: defaults).isBlocked("loudmouth"))

        blocklist.unblock("loudmouth")
        #expect(!blocklist.isBlocked("loudmouth"))
    }

    @Test func blocklistIsScopedToItsOwner() {
        let defaults = freshDefaults(#function)
        ChatBlocklist(ownerId: "owner-a", defaults: defaults).block("someone")

        #expect(ChatBlocklist(ownerId: "owner-b", defaults: defaults).isBlocked("someone") == false)
    }

    @Test func selfBlockIsIgnored() {
        let defaults = freshDefaults(#function)
        let blocklist = ChatBlocklist(ownerId: "owner", defaults: defaults)

        blocklist.block("owner")
        #expect(blocklist.blockedUserIds.isEmpty)
    }

    @Test func hidingAMessageRemovesItForTheReporter() {
        let defaults = freshDefaults(#function)
        let blocklist = ChatBlocklist(ownerId: "owner", defaults: defaults)

        blocklist.hide(messageId: "msg-1")
        #expect(blocklist.hiddenMessageIds.contains("msg-1"))
        #expect(!blocklist.hiddenMessageIds.contains("msg-2"))
    }

    @Test func pendingMessageSortsAsNewestUntilTheServerStamps() {
        let older = message(id: "older", createdAt: Date(timeIntervalSince1970: 1_000))
        let pending = message(id: "pending", createdAt: nil)

        #expect(pending.isPending)
        #expect(!older.isPending)
        #expect(older.sortDate < pending.sortDate)
    }

    @Test func textLimitMatchesTheRules() {
        // `firestore.rules` rejects anything over 500 characters; the client cap
        // has to agree or the composer fails with a permission error instead.
        #expect(ChatMessage.maxTextLength == 500)
    }

    @Test func initialsFallBackToTheDisplayName() {
        #expect(message(id: "a", displayName: "Dave Grohl").initials == "DA")
        #expect(message(id: "b", displayName: "  q").initials == "Q")
    }

    @Test func chatPushLandsOnGroupsRatherThanHome() {
        #expect(
            DeepLinkRouter.parseNotification(userInfo: ["type": "chat_message"]) == .openGroups
        )
    }

    private func message(
        id: String,
        displayName: String = "Tester",
        createdAt: Date? = Date()
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            groupId: "group-1",
            weekId: nil,
            userId: "user-1",
            displayName: displayName,
            avatarColorHex: "#DC2626",
            text: "Roll Tide",
            createdAt: createdAt,
            editedAt: nil,
            isDeleted: false,
            reactions: nil,
            reportCount: 0
        )
    }
}
