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
        #expect(message.contains("https://pickems-fb.web.app/join?code=ABC123"))
        #expect(InviteShare.universalURL(for: group)?.absoluteString == "https://pickems-fb.web.app/join?code=ABC123")
    }

    @Test func inviteUniversalLinksParseOnFirebaseHosting() {
        let url = URL(string: "https://pickems-fb.web.app/join?code=abc123")!
        #expect(DeepLinkRouter.parse(url: url) == .joinGroup(inviteCode: "ABC123"))
        let firebaseapp = URL(string: "https://pickems-fb.firebaseapp.com/join?code=xyz789")!
        #expect(DeepLinkRouter.parse(url: firebaseapp) == .joinGroup(inviteCode: "XYZ789"))
        let customScheme = URL(string: "pickems://join?code=abc123")!
        #expect(DeepLinkRouter.parse(url: customScheme) == .joinGroup(inviteCode: "ABC123"))
    }

    @Test func legalURLsAreHTTPS() {
        #expect(AppConfig.privacyPolicyURL?.scheme == "https")
        #expect(AppConfig.termsOfServiceURL?.scheme == "https")
        #expect(AppConfig.appStoreURL.contains("6785697079") || AppConfig.appStoreURL.contains("apps.apple.com"))
    }

    @Test func legalURLsPointAtMainBranchDocs() {
        let privacy = AppConfig.privacyPolicyURL?.absoluteString ?? ""
        let terms = AppConfig.termsOfServiceURL?.absoluteString ?? ""
        #expect(privacy.contains("/main/docs/privacy-policy.html"))
        #expect(terms.contains("/main/docs/terms.html"))
        #expect(!privacy.contains("cursor/"))
        #expect(!terms.contains("cursor/"))
    }

    @Test func unfinishedXIntegrationIsHidden() {
        #expect(AppConfig.isXSharingConfigured == false)
    }

    @Test func deleteAccountErrorsAreUserFacing() {
        #expect(AuthService.AuthError.requiresRecentLogin.errorDescription != nil)
        #expect(AuthService.AuthError.notSignedIn.errorDescription != nil)
    }

    @Test func displayNameUniquenessErrorsAreUserFacing() {
        #expect(AuthService.AuthError.displayNameTaken.errorDescription != nil)
        #expect(AuthService.AuthError.displayNameInvalid.errorDescription != nil)
    }
}
