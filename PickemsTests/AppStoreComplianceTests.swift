import Foundation
import Testing
@testable import Pickems

struct AppStoreComplianceTests {
    @Test func inviteMessageDoesNotPromiseTestFlight() {
        let group = PickemGroup(
            id: "g1",
            name: "Review League",
            inviteCode: "ABC123",
            commissionerId: "u1",
            memberIds: ["u1"],
            rules: .default,
            createdAt: Date()
        )
        let message = InviteShare.message(for: group)
        #expect(!message.localizedCaseInsensitiveContains("coming soon"))
        #expect(!message.localizedCaseInsensitiveContains("TestFlight"))
        #expect(message.contains(AppConfig.appStoreURL))
        #expect(message.contains("ABC123"))
    }

    @Test func legalURLsAreHTTPS() {
        #expect(AppConfig.privacyPolicyURL?.scheme == "https")
        #expect(AppConfig.termsOfServiceURL?.scheme == "https")
        #expect(AppConfig.appStoreURL.contains("6785697079") || AppConfig.appStoreURL.contains("apps.apple.com"))
    }

    @Test func unfinishedXIntegrationIsHidden() {
        #expect(AppConfig.isXSharingConfigured == false)
    }

    @Test func deleteAccountErrorsAreUserFacing() {
        #expect(AuthService.AuthError.requiresRecentLogin.errorDescription != nil)
        #expect(AuthService.AuthError.notSignedIn.errorDescription != nil)
    }
}
