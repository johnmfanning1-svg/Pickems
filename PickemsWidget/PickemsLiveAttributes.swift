import ActivityKit
import Foundation

/// Keep in sync with `Pickems/Features/Live/LiveActivityContent.swift`.
struct LiveActivityPick: Codable, Hashable {
    var gameId: String
    var picked: String
    var opponent: String
    var pickedScore: Int?
    var opponentScore: Int?
    var phase: String
    var result: String
    var resultLabel: String
    var kickoffUnix: Double
}

struct PickemsLiveAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var weeklyWins: Int
        var weeklyLosses: Int
        var weeklyPushes: Int
        var rank: Int?
        var rankTied: Bool
        var picks: [LiveActivityPick]
        var updatedAt: Double
        var contentVersion: Int

        var recordText: String {
            if weeklyPushes > 0 {
                return "\(weeklyWins)-\(weeklyLosses)-\(weeklyPushes)"
            }
            return "\(weeklyWins)-\(weeklyLosses)"
        }

        /// Nil at 0–0 so a join-order board cannot read as "#1".
        var rankText: String? {
            guard let rank, rank > 0, weeklyWins + weeklyLosses > 0 else { return nil }
            return rankTied ? "T-#\(rank)" : "#\(rank)"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            weeklyWins = try container.decodeIfPresent(Int.self, forKey: .weeklyWins) ?? 0
            weeklyLosses = try container.decodeIfPresent(Int.self, forKey: .weeklyLosses) ?? 0
            weeklyPushes = try container.decodeIfPresent(Int.self, forKey: .weeklyPushes) ?? 0
            rank = try container.decodeIfPresent(Int.self, forKey: .rank)
            rankTied = try container.decodeIfPresent(Bool.self, forKey: .rankTied) ?? false
            picks = try container.decodeIfPresent([LiveActivityPick].self, forKey: .picks) ?? []
            if container.contains(.updatedAt), let unix = try? container.decode(Double.self, forKey: .updatedAt) {
                updatedAt = unix
            } else {
                updatedAt = 0
            }
            contentVersion = try container.decodeIfPresent(Int.self, forKey: .contentVersion) ?? 0
            if !container.contains(.picks), weeklyWins + weeklyLosses == 0 {
                rank = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(weeklyWins, forKey: .weeklyWins)
            try container.encode(weeklyLosses, forKey: .weeklyLosses)
            try container.encode(weeklyPushes, forKey: .weeklyPushes)
            try container.encodeIfPresent(rank, forKey: .rank)
            try container.encode(rankTied, forKey: .rankTied)
            try container.encode(picks, forKey: .picks)
            try container.encode(updatedAt, forKey: .updatedAt)
            try container.encode(contentVersion, forKey: .contentVersion)
        }

        private enum CodingKeys: String, CodingKey {
            case weeklyWins
            case weeklyLosses
            case weeklyPushes
            case rank
            case rankTied
            case picks
            case updatedAt
            case contentVersion
        }
    }

    var groupId: String
    var groupName: String
    var weekId: String
    var weekNumber: Int
    var userDisplayName: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId) ?? ""
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? ""
        weekId = try container.decodeIfPresent(String.self, forKey: .weekId) ?? ""
        weekNumber = try container.decodeIfPresent(Int.self, forKey: .weekNumber) ?? 0
        userDisplayName = try container.decodeIfPresent(String.self, forKey: .userDisplayName) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(groupName, forKey: .groupName)
        try container.encode(weekId, forKey: .weekId)
        try container.encode(weekNumber, forKey: .weekNumber)
        try container.encode(userDisplayName, forKey: .userDisplayName)
    }

    private enum CodingKeys: String, CodingKey {
        case groupId
        case groupName
        case weekId
        case weekNumber
        case userDisplayName
    }
}

/// Keep in sync with `LiveActivityDestination` in the app target.
enum LiveActivityWidgetLink {
    static func url(groupId: String, weekId: String, picks: [LiveActivityPick]) -> URL? {
        let group = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let week = weekId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !group.isEmpty, !week.isEmpty else { return nil }
        let gameId: String
        if let live = picks.first(where: { $0.phase == "live" && !$0.gameId.isEmpty }) {
            gameId = live.gameId
        } else {
            gameId = picks.first(where: { !$0.gameId.isEmpty })?.gameId ?? ""
        }
        let tail = gameId.isEmpty ? "pickems" : "game/\(path(gameId))"
        return URL(string: "pickems://league/\(path(group))/week/\(path(week))/\(tail)")
    }

    private static func path(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
