import Foundation
import Testing
@testable import Pickems

struct NotificationPrefCategoryTests {
    @Test func missingPrefsDefaultToOn() {
        let profile = UserProfile(
            id: "u1",
            displayName: "Alex",
            avatarColorHex: "#DC2626",
            avatarImageURL: nil,
            createdAt: Date()
        )
        for category in NotificationPrefCategory.allCases {
            #expect(profile.wants(category))
        }
        #expect(profile.storedPref(.commissionerDeadlines) == nil)
        #expect(profile.enabledNotificationPrefCount == NotificationPrefCategory.memberFacing.count)
    }

    @Test func togglingACategoryDoesNotAffectOthers() {
        var profile = UserProfile(
            id: "u1",
            displayName: "Alex",
            avatarColorHex: "#DC2626",
            avatarImageURL: nil,
            createdAt: Date()
        )
        profile.set(.gameFinals, enabled: false)
        profile.set(.chatMessages, enabled: false)
        #expect(!profile.wants(.gameFinals))
        #expect(!profile.wants(.chatMessages))
        #expect(profile.wants(.weekScored))
        #expect(profile.wants(.selectionDeadlines))
        #expect(profile.enabledNotificationPrefCount == NotificationPrefCategory.memberFacing.count - 2)
    }

    @Test func eachPushTypeMapsToExactlyOneCategory() {
        let types = NotificationPrefCategory.allCases.flatMap(\.pushTypes)
        #expect(Set(types).count == types.count)
    }

    @Test func shouldDeliverHonorsCategorySwitches() {
        let disabled: Set<NotificationPrefCategory> = [.gameFinals, .pickemsDeadlines]
        #expect(
            !NotificationPrefCategory.shouldDeliver(type: "game_final") { !disabled.contains($0) }
        )
        #expect(
            !NotificationPrefCategory.shouldDeliver(type: "deadline_reminder") { !disabled.contains($0) }
        )
        #expect(
            NotificationPrefCategory.shouldDeliver(type: "chat_message") { !disabled.contains($0) }
        )
        #expect(
            NotificationPrefCategory.shouldDeliver(type: "week_scored") { !disabled.contains($0) }
        )
        #expect(
            NotificationPrefCategory.shouldDeliver(type: "unknown_future_type") { _ in false }
        )
    }

    @Test func firestoreFieldNamesMatchCloudFunctions() {
        #expect(NotificationPrefCategory.selectionDeadlines.firestoreField == "notifySelectionDeadlines")
        #expect(NotificationPrefCategory.pickemsDeadlines.firestoreField == "notifyPickemsDeadlines")
        #expect(NotificationPrefCategory.gameFinals.firestoreField == "notifyGameFinals")
        #expect(NotificationPrefCategory.tookTheLead.firestoreField == "notifyTookTheLead")
        #expect(NotificationPrefCategory.weekScored.firestoreField == "notifyWeekScored")
        #expect(NotificationPrefCategory.seasonClosed.firestoreField == "notifySeasonClosed")
        #expect(NotificationPrefCategory.chatMessages.firestoreField == "notifyChatMessages")
        #expect(NotificationPrefCategory.commissionerDeadlines.firestoreField == "notifyCommissionerDeadlines")
    }

    @Test func commissionerAlertsAreSeparateFromMemberSelectionReminders() {
        #expect(
            NotificationPrefCategory.selectionDeadlines.pushTypes.contains("selection_deadline_reminder")
        )
        #expect(
            !NotificationPrefCategory.selectionDeadlines.pushTypes.contains("set_selection_deadline")
        )
        #expect(
            NotificationPrefCategory.commissionerDeadlines.pushTypes.contains("set_selection_deadline")
        )
        #expect(
            NotificationPrefCategory.commissionerDeadlines.pushTypes.contains("selection_deadline_passed")
        )
    }

    @Test func leagueOverrideWinsThenFallsBackToAccountDefaults() {
        var defaults = UserProfile(
            id: "u1",
            displayName: "Alex",
            avatarColorHex: "#DC2626",
            avatarImageURL: nil,
            createdAt: Date()
        )
        defaults.set(.gameFinals, enabled: false)
        defaults.set(.chatMessages, enabled: true)

        var member = GroupMember(
            id: "u1",
            displayName: "Alex",
            avatarColorHex: "#DC2626",
            role: .member,
            joinedAt: Date(),
            seasonWins: 0,
            seasonLosses: 0
        )
        #expect(!member.wants(.gameFinals, defaults: defaults))
        #expect(member.wants(.chatMessages, defaults: defaults))

        member.set(.gameFinals, enabled: true)
        member.set(.chatMessages, enabled: false)
        #expect(member.wants(.gameFinals, defaults: defaults))
        #expect(!member.wants(.chatMessages, defaults: defaults))
        #expect(member.chatMuted == true)
    }

    @Test func legacySelectionOptOutSuppressesUnsetCommissionerAlerts() {
        var profile = UserProfile(
            id: "u1",
            displayName: "Alex",
            avatarColorHex: "#DC2626",
            avatarImageURL: nil,
            createdAt: Date()
        )
        profile.set(.selectionDeadlines, enabled: false)
        #expect(!profile.wants(.commissionerDeadlines))
        profile.set(.commissionerDeadlines, enabled: true)
        #expect(profile.wants(.commissionerDeadlines))
        #expect(!profile.wants(.selectionDeadlines))
    }

    @Test func inThreadChatMuteSuppressesLeagueChatEvenIfPrefIsOn() {
        var member = GroupMember(
            id: "u1",
            displayName: "Alex",
            avatarColorHex: "#DC2626",
            role: .member,
            joinedAt: Date(),
            seasonWins: 0,
            seasonLosses: 0
        )
        member.notifyChatMessages = true
        member.chatMuted = true
        let defaults = UserProfile(
            id: "u1",
            displayName: "Alex",
            avatarColorHex: "#DC2626",
            avatarImageURL: nil,
            createdAt: Date()
        )
        #expect(!member.wants(.chatMessages, defaults: defaults))
    }
}
