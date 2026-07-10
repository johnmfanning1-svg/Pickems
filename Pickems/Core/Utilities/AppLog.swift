import Foundation
import OSLog

/// Central OSLog facade. Filter in Console.app by subsystem `…Pickems` and category.
enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "FannypackInc.Pickems"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    static let firestore = Logger(subsystem: subsystem, category: "firestore")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let events = Logger(subsystem: subsystem, category: "events")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let picks = Logger(subsystem: subsystem, category: "picks")

    static func debug(_ logger: Logger, _ message: String, metadata: [String: String] = [:]) {
        #if DEBUG
        logger.debug("\(format(message, metadata: metadata), privacy: .public)")
        #endif
    }

    static func info(_ logger: Logger, _ message: String, metadata: [String: String] = [:]) {
        logger.info("\(format(message, metadata: metadata), privacy: .public)")
    }

    static func notice(_ logger: Logger, _ message: String, metadata: [String: String] = [:]) {
        logger.notice("\(format(message, metadata: metadata), privacy: .public)")
    }

    static func error(
        _ logger: Logger,
        _ message: String,
        error: Error? = nil,
        metadata: [String: String] = [:]
    ) {
        var meta = metadata
        if let error {
            meta["error"] = Self.describe(error)
            let nsError = error as NSError
            meta["ns_code"] = "\(nsError.domain):\(nsError.code)"
        }
        logger.error("\(format(message, metadata: meta), privacy: .public)")
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(error.localizedDescription) | domain=\(nsError.domain) | code=\(nsError.code)"
    }

    private static func format(_ message: String, metadata: [String: String]) -> String {
        guard !metadata.isEmpty else { return message }
        let pairs = metadata.keys.sorted().map { key in
            "\(key)=\(metadata[key] ?? "")"
        }
        return "\(message) {\(pairs.joined(separator: ", "))}"
    }
}
