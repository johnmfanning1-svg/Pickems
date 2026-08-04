import Foundation

enum CFBWeekSync {
    /// UserDefaults key for the last successful ESPN `CFBWeekInfo` week id (`"{year}-W{number}"`).
    /// Written by `persistLastKnownWeek` (called from `ESPNService.currentWeek` on success).
    /// Read first by `fallbackWeekId` so a failed ESPN call reuses the last good week instead of minting a divergent estimate.
    static let lastKnownWeekIdKey = "pickems.cfb.lastKnownWeekId"

    static func weekId(for info: CFBWeekInfo) -> String {
        "\(info.seasonYear)-W\(info.weekNumber)"
    }

    /// Persist a successful ESPN week so offline / failed refreshes reuse the same week doc id.
    static func persistLastKnownWeek(_ info: CFBWeekInfo, defaults: UserDefaults = .standard) {
        defaults.set(weekId(for: info), forKey: lastKnownWeekIdKey)
    }

    static func lastKnownWeekId(defaults: UserDefaults = .standard) -> String? {
        guard let id = defaults.string(forKey: lastKnownWeekIdKey), !id.isEmpty else { return nil }
        return id
    }

    static func fallbackWeekId(defaults: UserDefaults = .standard, on date: Date = Date()) -> String {
        if let known = lastKnownWeekId(defaults: defaults) {
            return known
        }
        let year = CFBSeasonCalendar.seasonYear(containing: date)
        let week = estimatedCFBWeek(on: date)
        return "\(year)-W\(week)"
    }

    /// Week number estimated from season kickoff (clamped to `1...15`). Prefer `lastKnownWeekId` via `fallbackWeekId` when available.
    static func estimatedCFBWeek(on date: Date = Date()) -> Int {
        let year = CFBSeasonCalendar.seasonYear(containing: date)
        let kickoff = CFBSeasonCalendar.seasonKickoff(forSeasonYear: year)
        if date < kickoff {
            return 1
        }
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let weeks = eastern.dateComponents([.weekOfYear], from: kickoff, to: date).weekOfYear ?? 0
        return max(1, min(15, weeks + 1))
    }

    static func makeWeekSummary(id: String, info: CFBWeekInfo, rules: GroupRules) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: info.seasonYear,
            weekNumber: info.weekNumber,
            status: .selection,
            slateSize: rules.slateSize,
            selectionMode: rules.selectionMode,
            selectionsPerMember: rules.selectionsPerMember,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0
        )
    }
}
