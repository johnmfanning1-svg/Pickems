import Foundation
import Testing
import UserNotifications
@testable import Pickems

struct PushRegistrationPolicyTests {
    @Test func authorizedStatusesRegisterForAPNs() {
        #expect(PushRegistrationPolicy.shouldRegisterForRemoteNotifications(.authorized))
        #expect(PushRegistrationPolicy.shouldRegisterForRemoteNotifications(.provisional))
        #expect(PushRegistrationPolicy.shouldRegisterForRemoteNotifications(.ephemeral))
    }

    @Test func deniedAndUndeterminedDoNotRegister() {
        #expect(!PushRegistrationPolicy.shouldRegisterForRemoteNotifications(.denied))
        #expect(!PushRegistrationPolicy.shouldRegisterForRemoteNotifications(.notDetermined))
    }
}
