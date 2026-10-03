import Foundation
import FirebaseAuth
import FirebaseCore

/// Calls a Firebase HTTPS callable (`onCall`) over plain HTTPS with the signed-in
/// user's ID token, so the app does not need the FirebaseFunctions SDK.
/// Wire format: https://firebase.google.com/docs/functions/callable-reference
enum CloudFunctionsClient {
    /// Callables in `firebase/functions` deploy to the default region.
    static let region = "us-central1"

    struct CallableError: LocalizedError, Equatable {
        /// Callable status, e.g. `PERMISSION_DENIED`, `FAILED_PRECONDITION`, `NOT_FOUND`.
        let status: String
        let message: String

        var errorDescription: String? { message }
    }

    static func url(projectID: String, function name: String) -> URL? {
        URL(string: "https://\(region)-\(projectID).cloudfunctions.net/\(name)")
    }

    /// Returns the callable's `result` object (empty when it returned none).
    static func call(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        guard let projectID = FirebaseApp.app()?.options.projectID,
              let endpoint = url(projectID: projectID, function: name) else {
            throw CallableError(
                status: "UNAVAILABLE",
                message: "Couldn't reach Pickems right now. Try again in a moment."
            )
        }
        guard let user = Auth.auth().currentUser else {
            throw CallableError(status: "UNAUTHENTICATED", message: "Sign in again, then try that again.")
        }
        let token = try await user.getIDToken()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])

        let (body, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try parse(body: body, statusCode: statusCode)
    }

    /// Split out so the callable envelope can be unit-tested without the network.
    static func parse(body: Data, statusCode: Int) throws -> [String: Any] {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            let status = error["status"] as? String ?? "UNKNOWN"
            let raw = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Callables send "INTERNAL" for unexpected server errors — not useful copy.
            let message = raw.isEmpty || raw == status ? "Something went wrong. Please try again." : raw
            throw CallableError(status: status, message: message)
        }
        guard (200..<300).contains(statusCode) else {
            if statusCode == 404 {
                throw CallableError(
                    status: "NOT_FOUND",
                    message: "This needs a Pickems server update that isn't live yet. Try again later."
                )
            }
            throw CallableError(status: "INTERNAL", message: "Something went wrong. Please try again.")
        }
        return json?["result"] as? [String: Any] ?? [:]
    }
}
