import Foundation

/// Shared App Group payload for widgets and Live Activities.
struct StandingsSnapshot: Codable, Equatable {
    var groupId: String
    var groupName: String
    var weekNumber: Int
    var seasonYear: Int
    var userId: String
    var userDisplayName: String
    var weeklyWins: Int
    var weeklyLosses: Int
    var seasonWins: Int
    var seasonLosses: Int
    var rank: Int
    var totalPlayers: Int
    var topEntries: [SnapshotEntry]
    var updatedAt: Date
    /// When set and still in the future, the widget shows a kickoff countdown instead of standings.
    var seasonKickoffAt: Date? = nil
    /// Member nomination deadline while this week is still in Selections.
    var selectionsDeadline: Date? = nil
    /// Pickems lock. Usually the first slate kickoff.
    var pickemsDeadline: Date? = nil
    /// True when each game locks at its own kickoff.
    var rollingLock: Bool? = nil
    /// Scoreboard rows. Nil on snapshots written before this field existed.
    var games: [SnapshotGame]? = nil
    /// Earliest still-open kickoff when `rollingLock` is true.
    var nextLockAt: Date? = nil
    /// Ignored when choosing a phase. The widget computes that from the fields above.
    var weekPhaseHint: String? = nil

    struct SnapshotGame: Codable, Equatable, Identifiable {
        var id: String
        var awayShortName: String
        var homeShortName: String
        var kickoff: Date
        var isLocked: Bool
        var isFinal: Bool
        var awayScore: Int?
        var homeScore: Int?
        /// Abbreviation of the team the user picked.
        var userPick: String?
        var result: SnapshotPickResult
    }

    enum SnapshotPickResult: String, Codable, Equatable {
        case win
        case loss
        case push
        case pending
    }

    struct SnapshotEntry: Codable, Equatable, Identifiable {
        var id: String
        var displayName: String
        var weeklyWins: Int
        var weeklyLosses: Int
        var seasonWins: Int
        var seasonLosses: Int
        var rank: Int
    }

    var weeklyRecord: String { "\(weeklyWins)-\(weeklyLosses)" }
    var seasonRecord: String { "\(seasonWins)-\(seasonLosses)" }

    var showsPreseasonCountdown: Bool {
        guard let seasonKickoffAt else { return false }
        return Date() < seasonKickoffAt
    }
}

enum PickemsAppGroup {
    static let suiteName = "group.FannypackInc.Pickems"
    static let standingsKey = "standingsSnapshot"
    static let displayGroupIdKey = "widgetDisplayGroupId"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func save(_ snapshot: StandingsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: standingsKey)
    }

    static func load() -> StandingsSnapshot? {
        guard let data = defaults?.data(forKey: standingsKey) else { return nil }
        return try? JSONDecoder().decode(StandingsSnapshot.self, from: data)
    }

    static func clear() {
        defaults?.removeObject(forKey: standingsKey)
    }

    static func displayGroupId() -> String? {
        guard let id = defaults?.string(forKey: displayGroupIdKey), !id.isEmpty else { return nil }
        return id
    }

    static func setDisplayGroupId(_ id: String?) {
        if let id, !id.isEmpty {
            defaults?.set(id, forKey: displayGroupIdKey)
        } else {
            defaults?.removeObject(forKey: displayGroupIdKey)
        }
    }
}
