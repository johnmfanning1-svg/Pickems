import Foundation

enum AppConfig {
    /// Replace with your X Developer Portal OAuth 2.0 Client ID.
    static let xClientID = "YOUR_X_CLIENT_ID"

    /// Custom URL scheme registered in Info.plist for OAuth callback.
    static let xRedirectScheme = "pickems"
    static let xRedirectURI = "pickems://x-callback"

    /// App promotion link appended to shared posts.
    static let appPromoURL = "https://pickems.app"

    /// App Store product page (Apple ID 6785697079).
    static let appStoreURL = "https://apps.apple.com/app/id6785697079"

    /// Hosted legal pages (GitHub Pages from /docs until pickems.app is live).
    static let privacyPolicyURL = URL(string: "https://johnmfanning1-svg.github.io/Pickems/privacy-policy.html")
    static let termsOfServiceURL = URL(string: "https://johnmfanning1-svg.github.io/Pickems/terms.html")

    static var isXSharingConfigured: Bool {
        !xClientID.isEmpty && xClientID != "YOUR_X_CLIENT_ID"
    }

    static let appHashtag = "#Pickems"
    static let cfbHashtag = "#CFB"
}
