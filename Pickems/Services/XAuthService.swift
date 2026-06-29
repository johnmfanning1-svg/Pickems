import AuthenticationServices
import CryptoKit
import Foundation
import Security

@MainActor
final class XAuthService: NSObject, ObservableObject {
    @Published private(set) var tokens: XAuthTokens?
    @Published private(set) var isConnecting = false
    @Published var lastError: XAuthError?

    private let tokenStorageKey = "pickems.xauth.tokens"
    private var authSession: ASWebAuthenticationSession?
    private var codeVerifier: String?

    override init() {
        super.init()
        tokens = loadTokens()
    }

    var isConnected: Bool {
        tokens != nil
    }

    var connectedUsername: String? {
        tokens?.xUsername
    }

    func connect() async throws {
        guard AppConfig.xClientID != "YOUR_X_CLIENT_ID" else {
            throw XAuthError.notConfigured
        }

        isConnecting = true
        lastError = nil
        defer { isConnecting = false }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(length: 32)
        codeVerifier = verifier

        guard let authURL = XURLBuilder.authorizeURL(
            clientID: AppConfig.xClientID,
            redirectURI: AppConfig.xRedirectURI,
            state: state,
            codeChallenge: challenge
        ) else {
            throw XAuthError.notConfigured
        }

        let callbackURL = try await startAuthSession(url: authURL, callbackScheme: AppConfig.xRedirectScheme)
        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
            returnedState == state
        else {
            throw XAuthError.invalidCallback
        }

        let exchanged = try await exchangeCode(code, verifier: verifier)
        tokens = exchanged
        saveTokens(exchanged)
    }

    func disconnect() {
        tokens = nil
        codeVerifier = nil
        UserDefaults.standard.removeObject(forKey: tokenStorageKey)
    }

    func validAccessToken() async throws -> String {
        guard var current = tokens else {
            throw XAuthError.notConnected
        }

        if current.isExpired, let refreshToken = current.refreshToken {
            current = try await refreshTokens(refreshToken)
            tokens = current
            saveTokens(current)
        }

        return current.accessToken
    }

    private func startAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: XAuthError.cancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: XAuthError.invalidCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            authSession = session
            session.start()
        }
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> XAuthTokens {
        var request = URLRequest(url: XURLBuilder.tokenExchangeURL())
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": AppConfig.xClientID,
            "redirect_uri": AppConfig.xRedirectURI,
            "code_verifier": verifier
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw XAuthError.tokenExchangeFailed
        }

        return try parseTokenResponse(data)
    }

    private func refreshTokens(_ refreshToken: String) async throws -> XAuthTokens {
        var request = URLRequest(url: XURLBuilder.tokenExchangeURL())
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
            "client_id": AppConfig.xClientID
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw XAuthError.tokenExchangeFailed
        }

        return try parseTokenResponse(data, existing: tokens)
    }

    private func parseTokenResponse(_ data: Data, existing: XAuthTokens? = nil) throws -> XAuthTokens {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let accessToken = json?["access_token"] as? String else {
            throw XAuthError.tokenExchangeFailed
        }

        let expiresIn = json?["expires_in"] as? TimeInterval
        let expiresAt = expiresIn.map { Date().addingTimeInterval($0) }

        return XAuthTokens(
            accessToken: accessToken,
            refreshToken: json?["refresh_token"] as? String ?? existing?.refreshToken,
            expiresAt: expiresAt,
            scope: json?["scope"] as? String,
            xUserId: existing?.xUserId,
            xUsername: existing?.xUsername
        )
    }

    private func saveTokens(_ tokens: XAuthTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        UserDefaults.standard.set(data, forKey: tokenStorageKey)
    }

    private func loadTokens() -> XAuthTokens? {
        guard
            let data = UserDefaults.standard.data(forKey: tokenStorageKey),
            let tokens = try? JSONDecoder().decode(XAuthTokens.self, from: data)
        else {
            return nil
        }
        return tokens
    }

    private static func randomURLSafeString(length: Int) -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension XAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
