import Foundation
import Testing
@testable import Pickems

struct AppEventsTests {
    @Test func redactsSensitiveMetadata() {
        let redacted = AppEvents.redact([
            "email": "user@example.com",
            "password": "secret",
            "token": "abc",
            "method": "apple",
            "uid": "12345678",
        ])
        #expect(redacted["email"] == "<redacted>")
        #expect(redacted["password"] == "<redacted>")
        #expect(redacted["token"] == "<redacted>")
        #expect(redacted["method"] == "apple")
        #expect(redacted["uid"] == "12345678")
    }

    @Test func shortUIDTruncates() {
        #expect(AppEvents.shortUID("abcdefghijklmnop") == "abcdefgh")
        #expect(AppEvents.shortUID(nil) == "nil")
        #expect(AppEvents.shortUID("") == "nil")
    }

    @Test func eventRawValuesAreStableDotPaths() {
        #expect(AppEvent.authSignInFailed.rawValue == "auth.sign_in_failed")
        #expect(AppEvent.rootDestinationChanged.rawValue == "root.destination_changed")
        #expect(AppEvent.onboardingJoinSucceeded.rawValue == "onboarding.join_succeeded")
        #expect(AppEvent.sessionBootstrapFailed.rawValue == "session.bootstrap_failed")
        #expect(AppEvent.notificationsTokenSaved.rawValue == "notifications.token_saved")
        #expect(AppEvent.notificationsAPNsFailed.rawValue == "notifications.apns_failed")
    }
}
