import Foundation

enum AppConfig {
    /// Replace with your X Developer Portal OAuth 2.0 Client ID.
    static let xClientID = "YOUR_X_CLIENT_ID"

    /// Custom URL scheme registered in Info.plist for OAuth callback.
    static let xRedirectScheme = "pickems"
    static let xRedirectURI = "pickems://x-callback"

    /// App promotion link appended to shared posts.
    static let appPromoURL = "https://pickems.app"

    /// App Store link — update when published.
    static let appStoreURL = "https://apps.apple.com/app/pickems"

    static let appHashtag = "#Pickems"
    static let cfbHashtag = "#CFB"
}
