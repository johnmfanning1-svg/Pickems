import Foundation

/// Shared App Group payload for widgets, Live Activities, and Watch.
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
