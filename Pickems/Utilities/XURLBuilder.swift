import Foundation

enum XURLBuilder {
    /// Opens X compose with pre-filled tweet text (no API key required).
    static func intentTweetURL(text: String) -> URL? {
        var components = URLComponents(string: "https://twitter.com/intent/tweet")
        components?.queryItems = [
            URLQueryItem(name: "text", value: text)
        ]
        return components?.url
    }

    /// X OAuth 2.0 authorize URL with PKCE.
    static func authorizeURL(
        clientID: String,
        redirectURI: String,
        state: String,
        codeChallenge: String
    ) -> URL? {
        var components = URLComponents(string: "https://twitter.com/i/oauth2/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "tweet.read tweet.write users.read offline.access"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }

    static func tokenExchangeURL() -> URL {
        URL(string: "https://api.twitter.com/2/oauth2/token")!
    }

    static func postTweetURL() -> URL {
        URL(string: "https://api.twitter.com/2/tweets")!
    }
}
