import Foundation
import Testing
@testable import Pickems

struct LaunchSafetyTests {
    @Test func authRoutingNeverSkipsLoadingBeforeAuthSettles() {
        #expect(
            AuthRouting.destination(
                authStateDetermined: false,
                isAuthenticated: true,
                needsOnboarding: false
            ) == .loading
        )
    }

    @Test func signedOutNeverLandsInMain() {
        #expect(
            AuthRouting.destination(
                authStateDetermined: true,
                isAuthenticated: false,
                needsOnboarding: false
            ) == .signIn
        )
    }

    @Test func deepLinkNotificationParseIsNonThrowing() {
        #expect(DeepLinkRouter.parseNotification(userInfo: [:]) == nil)
        #expect(
            DeepLinkRouter.parseNotification(userInfo: ["type": "week_scored"]) == .openPickems(groupId: nil)
        )
        #expect(
            DeepLinkRouter.parseNotification(userInfo: ["type": "season_closed"]) == .openLeagues(groupId: nil)
        )
        #expect(
            DeepLinkRouter.parseNotification(userInfo: [
                "type": "selection_deadline_reminder",
                "groupId": "g1",
            ]) == .openSelections(groupId: "g1")
        )
        #expect(
            DeepLinkRouter.parseNotification(userInfo: [
                "type": "deadline_reminder",
                "groupId": "g1",
            ]) == .openPickems(groupId: "g1")
        )
        // Ensure malformed payloads never trap.
        let junk: [AnyHashable: Any] = [
            "aps": ["alert": "hi"],
            "action": 123,
            "url": NSNull(),
        ]
        #expect(DeepLinkRouter.parseNotification(userInfo: junk) == nil)
    }
}
