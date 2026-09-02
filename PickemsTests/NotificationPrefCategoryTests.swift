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
        #expect(profile.enabledNotificationPrefCount == NotificationPrefCategory.allCases.count)
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
        #expect(profile.enabledNotificationPrefCount == NotificationPrefCategory.allCases.count - 2)
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
    }
}
