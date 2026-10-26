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
    /// One game on the Pickems tab for that league and week.
    case openGame(groupId: String, weekId: String, gameId: String)
    /// League Pickems for a week, with no single game (combined no-pick).
    case openWeekPickems(groupId: String, weekId: String)
    /// Leagues tab, This Week, for a lead alert.
    case openLeaderboard(groupId: String, weekId: String)
}

/// What a game-final, no-pick, or lead tap should do once membership is known.
enum NotificationLaunch: Equatable, Sendable {
    /// Groups have not loaded yet (cold launch). Keep the route and try again.
    case deferred
    /// The member is no longer in that league.
    case home
    case pickems(groupId: String, weekId: String, gameId: String?)
    case leaderboard(groupId: String, weekId: String)

    /// `nil` means this action is not one of the game/lead routes.
    nonisolated static func resolve(
        action: DeepLinkAction,
        groupsLoaded: Bool,
        memberGroupIds: [String]
    ) -> NotificationLaunch? {
        let groupId: String
        let target: NotificationLaunch
        switch action {
        case .openGame(let id, let weekId, let gameId):
            groupId = id
            target = .pickems(groupId: id, weekId: weekId, gameId: gameId)
        case .openWeekPickems(let id, let weekId):
            groupId = id
            target = .pickems(groupId: id, weekId: weekId, gameId: nil)
        case .openLeaderboard(let id, let weekId):
            groupId = id
            target = .leaderboard(groupId: id, weekId: weekId)
        default:
            return nil
        }
        guard groupsLoaded else { return .deferred }
        guard memberGroupIds.contains(groupId) else { return .home }
        return target
    }

    /// Manual This Week choice for the lead-alert league.
    static func leaderboardChoice(leagueId: String) -> LeaderboardScope.ManualChoice {
        LeaderboardScope.ManualChoice(leagueId: leagueId, scope: .thisWeek)
    }
}

enum DeepLinkRouter {
    /// nonisolated: AppDelegate notification callbacks run off the main actor under Swift 6.
    nonisolated static func parse(url: URL) -> DeepLinkAction? {
        if url.scheme?.lowercased() == "pickems" {
            if (url.host ?? "").lowercased() == "league" {
                return parseLeaguePath(url.path)
            }
            return parseHost(path: url.host ?? "", query: url.queryItems)
        }
        if isUniversalLinkHost(url.host) {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.lowercased().hasPrefix("league/") || path.lowercased() == "league" {
                return parseLeaguePath(path)
            }
            return parseHost(path: path, query: url.queryItems)
        }
        return nil
    }

    /// nonisolated: must be safe to call from `UNUserNotificationCenter` completion handlers.
    nonisolated static func parseNotification(userInfo: [AnyHashable: Any]) -> DeepLinkAction? {
        if let link = stringValue(userInfo["deepLink"]),
           let url = URL(string: link),
           let action = parse(url: url) {
            return action
        }
        guard let type = stringValue(userInfo["type"]) else { return nil }
        let groupId = stringValue(userInfo["groupId"])
        let weekId = stringValue(userInfo["weekId"])
        let gameId = stringValue(userInfo["gameId"])
        switch type {
        case "week_scored", "deadline_reminder", "deadline_locked", "pickems_open":
            return .openPickems(groupId: groupId)
        case "deadline_passed", "season_closed", "chat_message", "coordinator_role":
            return .openLeagues(groupId: groupId)
        case "set_selection_deadline":
            return .openSelectionDeadline(groupId: groupId)
        case "selection_deadline_passed", "selection_deadline_reminder":
            return .openSelections(groupId: groupId)
        case "game_final", "selection_veto":
            if let groupId, let weekId, let gameId {
                return .openGame(groupId: groupId, weekId: weekId, gameId: gameId)
            }
            return .openLiveSlate(groupId: groupId)
        case "no_pick":
            if let groupId, let weekId, let gameId {
                return .openGame(groupId: groupId, weekId: weekId, gameId: gameId)
            }
            if let groupId, let weekId {
                return .openWeekPickems(groupId: groupId, weekId: weekId)
            }
            return .openPickems(groupId: groupId)
        case "lead":
            if let groupId, let weekId {
                return .openLeaderboard(groupId: groupId, weekId: weekId)
            }
            return .openLeagues(groupId: groupId)
        case "took_the_lead":
            if let groupId, let weekId {
                return .openLeaderboard(groupId: groupId, weekId: weekId)
            }
            return .openLiveSlate(groupId: groupId)
        default:
            return .openHome
        }
    }

    nonisolated static func parseLeaguePath(_ rawPath: String) -> DeepLinkAction? {
        var parts = rawPath
            .split(separator: "/")
            .map { segment -> String in
                let text = String(segment)
                return text.removingPercentEncoding ?? text
            }
        if parts.first?.lowercased() == "league" {
            parts.removeFirst()
        }
        guard parts.count >= 3, parts[1].lowercased() == "week" else { return nil }
        let groupId = parts[0]
        let weekId = parts[2]
        guard !groupId.isEmpty, !weekId.isEmpty else { return nil }
        if parts.count >= 5, parts[3].lowercased() == "game" {
            let gameId = parts[4]
            guard !gameId.isEmpty else { return nil }
            return .openGame(groupId: groupId, weekId: weekId, gameId: gameId)
        }
        if parts.count >= 4, parts[3].lowercased() == "leaderboard" {
            return .openLeaderboard(groupId: groupId, weekId: weekId)
        }
        if parts.count == 3 || (parts.count >= 4 && parts[3].lowercased() == "pickems") {
            return .openWeekPickems(groupId: groupId, weekId: weekId)
        }
        return nil
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

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension URL {
    nonisolated var queryItems: [URLQueryItem]? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems
    }
}
