import Combine
import Foundation
import UIKit

enum XShareMethod {
    case xIntent
    case shareSheet
    case directAPI
}

@MainActor
final class XShareService: ObservableObject {
    @Published var lastError: XAuthError?
    @Published var lastPostedTweetID: String?

    private let authService: XAuthService

    init(authService: XAuthService) {
        self.authService = authService
    }

    func openXIntent(for result: ShareableResult) {
        guard let url = XURLBuilder.intentTweetURL(text: result.tweetText) else { return }
        UIApplication.shared.open(url)
    }

    func openXIntent(text: String) {
        guard let url = XURLBuilder.intentTweetURL(text: text) else { return }
        UIApplication.shared.open(url)
    }

    func shareSheetItems(for result: ShareableResult, image: UIImage?) -> [Any] {
        var items: [Any] = [result.shareSheetText]
        if let image {
            items.append(image)
        }
        return items
    }

    func shareSheetItems(text: String) -> [Any] {
        [text]
    }

    func postDirectly(for result: ShareableResult) async throws {
        try await postDirectly(text: result.tweetText)
    }

    func postDirectly(text: String) async throws {
        let accessToken = try await authService.validAccessToken()

        var request = URLRequest(url: XURLBuilder.postTweetURL())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = ["text": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw XAuthError.postFailed("Invalid response")
        }

        if (200...299).contains(http.statusCode) {
            if
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tweetData = json["data"] as? [String: Any],
                let tweetID = tweetData["id"] as? String
            {
                lastPostedTweetID = tweetID
            }
            return
        }

        let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
        lastError = .postFailed(message)
        throw XAuthError.postFailed(message)
    }

    func preferredMethod(isXConnected: Bool) -> XShareMethod {
        isXConnected ? .directAPI : .xIntent
    }
}
