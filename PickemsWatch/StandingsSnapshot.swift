import Foundation

/// Duplicated App Group reader for watchOS target.
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
    /// When set and still in the future, Home Screen / Watch can show a Week 0 countdown.
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
}

enum PickemsAppGroup {
    static let suiteName = "group.FannypackInc.Pickems"
    static let standingsKey = "standingsSnapshot"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func load() -> StandingsSnapshot? {
        guard let data = defaults?.data(forKey: standingsKey) else { return nil }
        return try? JSONDecoder().decode(StandingsSnapshot.self, from: data)
    }
}
