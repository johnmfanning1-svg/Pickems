import Foundation

enum DeepLinkAction: Equatable {
    case joinGroup(inviteCode: String)
    case openPicks
    case openGroups
    case openHome
}

enum DeepLinkRouter {
    static func parse(url: URL) -> DeepLinkAction? {
        if url.scheme?.lowercased() == "pickems" {
            return parseHost(path: url.host ?? "", query: url.queryItems)
        }
        if url.host?.contains("pickems.app") == true {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return parseHost(path: path, query: url.queryItems)
        }
        return nil
    }

    static func parseNotification(userInfo: [AnyHashable: Any]) -> DeepLinkAction? {
        guard let type = userInfo["type"] as? String else { return nil }
        switch type {
        case "week_scored", "deadline_reminder", "deadline_locked":
            return .openPicks
        case "deadline_passed":
            return .openGroups
        default:
            return .openHome
        }
    }

    private static func parseHost(path: String, query: [URLQueryItem]?) -> DeepLinkAction? {
        switch path.lowercased() {
        case "join":
            if let code = query?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
                return .joinGroup(inviteCode: code.uppercased())
            }
            return nil
        case "picks":
            return .openPicks
        case "groups":
            return .openGroups
        default:
            return nil
        }
    }
}

private extension URL {
    var queryItems: [URLQueryItem]? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems
    }
}
