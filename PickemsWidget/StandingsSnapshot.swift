import Foundation

/// Copy of shared snapshot model for the widget extension target.
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
}
