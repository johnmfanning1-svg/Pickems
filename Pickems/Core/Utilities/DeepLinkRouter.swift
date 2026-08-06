import Foundation

enum DeepLinkAction: Equatable, Sendable {
    case joinGroup(inviteCode: String)
    case openPicks
    case openGroups
    case openHome
    case openDiscover
    case openLiveSlate
    case openSelectionDeadline
}

enum DeepLinkRouter {
    /// nonisolated: AppDelegate notification callbacks run off the main actor under Swift 6.
    nonisolated static func parse(url: URL) -> DeepLinkAction? {
        if url.scheme?.lowercased() == "pickems" {
            return parseHost(path: url.host ?? "", query: url.queryItems)
        }
        if url.host?.contains("pickems.app") == true {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return parseHost(path: path, query: url.queryItems)
        }
        return nil
    }

    /// nonisolated: must be safe to call from `UNUserNotificationCenter` completion handlers.
    nonisolated static func parseNotification(userInfo: [AnyHashable: Any]) -> DeepLinkAction? {
        guard let type = userInfo["type"] as? String else { return nil }
        switch type {
        case "week_scored", "deadline_reminder", "deadline_locked":
            return .openPicks
        case "deadline_passed", "season_closed", "chat_message":
            // Chat is reached from Groups, so that tab is the closest landing spot.
            return .openGroups
        case "set_selection_deadline", "selection_deadline_passed":
            return .openSelectionDeadline
        case "game_final", "took_the_lead":
            return .openLiveSlate
        default:
            return .openHome
        }
    }

    nonisolated private static func parseHost(path: String, query: [URLQueryItem]?) -> DeepLinkAction? {
        switch path.lowercased() {
        case "join":
            if let code = query?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
                return .joinGroup(inviteCode: code.uppercased())
            }
            return nil
        case "picks", "live":
            return path.lowercased() == "live" ? .openLiveSlate : .openPicks
        case "groups":
            return .openGroups
        case "discover":
            return .openDiscover
        default:
            return nil
        }
    }
}

private extension URL {
    nonisolated var queryItems: [URLQueryItem]? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems
    }
}
