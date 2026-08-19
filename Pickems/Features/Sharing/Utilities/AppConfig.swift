import Foundation

enum AppConfig {
    /// Replace with your X Developer Portal OAuth 2.0 Client ID.
    static let xClientID = "YOUR_X_CLIENT_ID"

    /// Custom URL scheme registered in Info.plist for OAuth callback.
    static let xRedirectScheme = "pickems"
    static let xRedirectURI = "pickems://x-callback"

    /// App promotion link appended to shared posts.
    static let appPromoURL = "https://pickems-fb.web.app"

    /// Hosted invite links (Universal Links). Must match Associated Domains.
    static let inviteWebHost = "pickems-fb.web.app"
    static var inviteJoinBaseURL: String { "https://\(inviteWebHost)" }

    /// App Store product page (Apple ID 6785697079).
    static let appStoreURL = "https://apps.apple.com/app/id6785697079"

    /// Hosted legal pages on `main` (raw GitHub is publicly reachable HTTPS for App Review).
    static let privacyPolicyURL = URL(string: "https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/main/docs/privacy-policy.html")
    static let termsOfServiceURL = URL(string: "https://raw.githubusercontent.com/johnmfanning1-svg/Pickems/main/docs/terms.html")

    static var isXSharingConfigured: Bool {
        !xClientID.isEmpty && xClientID != "YOUR_X_CLIENT_ID"
    }

    static let appHashtag = "#Pickems"
    static let cfbHashtag = "#CFB"
}
