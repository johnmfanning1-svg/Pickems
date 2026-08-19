import Foundation

enum DeepLinkAction: Equatable, Sendable {
    case joinGroup(inviteCode: String)
    case openPickems(groupId: String?)
    case openSelections(groupId: String?)
    case openLeagues(groupId: String?)
    case openHome
    case openDiscover
    case openLiveSlate(groupId: String?)
    case openSelectionDeadline(groupId: String?)
}

enum DeepLinkRouter {
    /// nonisolated: AppDelegate notification callbacks run off the main actor under Swift 6.
    nonisolated static func parse(url: URL) -> DeepLinkAction? {
        if url.scheme?.lowercased() == "pickems" {
            return parseHost(path: url.host ?? "", query: url.queryItems)
        }
        if isUniversalLinkHost(url.host) {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return parseHost(path: path, query: url.queryItems)
        }
        return nil
    }

    /// nonisolated: must be safe to call from `UNUserNotificationCenter` completion handlers.
    nonisolated static func parseNotification(userInfo: [AnyHashable: Any]) -> DeepLinkAction? {
        guard let type = userInfo["type"] as? String else { return nil }
        let groupId = userInfo["groupId"] as? String
        switch type {
        case "week_scored", "deadline_reminder", "deadline_locked", "pickems_open":
            return .openPickems(groupId: groupId)
        case "deadline_passed", "season_closed", "chat_message":
            return .openLeagues(groupId: groupId)
        case "set_selection_deadline":
            return .openSelectionDeadline(groupId: groupId)
        case "selection_deadline_passed", "selection_deadline_reminder":
            return .openSelections(groupId: groupId)
        case "game_final", "took_the_lead":
            return .openLiveSlate(groupId: groupId)
        default:
            return .openHome
        }
    }

    nonisolated private static func isUniversalLinkHost(_ host: String?) -> Bool {
        guard let host else { return false }
        switch host.lowercased() {
        case "pickems.app",
             "www.pickems.app",
             "pickems-fb.web.app",
             "pickems-fb.firebaseapp.com":
            return true
        default:
            return false
        }
    }

    nonisolated private static func parseHost(path: String, query: [URLQueryItem]?) -> DeepLinkAction? {
        let groupId = query?.first(where: { $0.name == "group" })?.value
        switch path.lowercased() {
        case "join":
            if let code = query?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
                return .joinGroup(inviteCode: code.uppercased())
            }
            return nil
        case "picks", "pickems":
            return .openPickems(groupId: groupId)
        case "selections", "slate":
            return .openSelections(groupId: groupId)
        case "live":
            return .openLiveSlate(groupId: groupId)
        case "groups", "leagues":
            return .openLeagues(groupId: groupId)
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
