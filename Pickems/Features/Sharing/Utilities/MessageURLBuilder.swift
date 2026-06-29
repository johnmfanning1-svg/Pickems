import Foundation

enum MessageURLBuilder {
    /// Fallback when MessageUI compose is unavailable (e.g. Simulator).
    static func smsURL(body: String) -> URL? {
        var components = URLComponents(string: "sms:")
        components?.queryItems = [
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }
}
