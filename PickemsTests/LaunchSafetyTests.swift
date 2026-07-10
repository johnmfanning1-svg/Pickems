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
            DeepLinkRouter.parseNotification(userInfo: ["type": "week_scored"]) == .openPicks
        )
        #expect(
            DeepLinkRouter.parseNotification(userInfo: ["type": "season_closed"]) == .openGroups
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
