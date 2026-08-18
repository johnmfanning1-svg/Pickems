import Foundation

enum CFBWeekSync {
    /// UserDefaults key for the last successful Pickems week id (`"{year}-W{number}"`).
    /// Written by `persistLastKnownWeek` (called from `ESPNService.currentWeek` on success).
    /// Read first by `fallbackWeekId` so a failed ESPN call reuses the last good week instead of minting a divergent estimate.
    static let lastKnownWeekIdKey = "pickems.cfb.lastKnownWeekId"

    static func weekId(for info: CFBWeekInfo, now: Date = Date()) -> String {
        CFBWeekCalendar.resolve(espn: info, now: now).id
    }

    static func parseWeekId(_ id: String) -> (seasonYear: Int, weekNumber: Int)? {
        let parts = id.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]) else { return nil }
        let weekPart = parts[1]
        guard weekPart.hasPrefix("W"), let number = Int(weekPart.dropFirst()) else { return nil }
        return (year, number)
    }

    /// Persist a successful ESPN week so offline / failed refreshes reuse the same week doc id.
    static func persistLastKnownWeek(_ info: CFBWeekInfo, defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(weekId(for: info, now: now), forKey: lastKnownWeekIdKey)
    }

    static func lastKnownWeekId(defaults: UserDefaults = .standard) -> String? {
        guard let id = defaults.string(forKey: lastKnownWeekIdKey), !id.isEmpty else { return nil }
        return id
    }

    static func fallbackWeekId(defaults: UserDefaults = .standard, on date: Date = Date()) -> String {
        let resolved = resolvedFallback(on: date)
        if let known = lastKnownWeekId(defaults: defaults) {
            // Pre-overlay clients cached ESPN's 2026-W1. Prefer Week 0 while that window is open.
            if resolved.weekNumber == 0, known == "\(resolved.seasonYear)-W1" {
                return resolved.id
            }
            return known
        }
        return resolved.id
    }

    /// Week number estimated from season kickoff (clamped to `1...15`). Prefer `lastKnownWeekId` via `fallbackWeekId` when available.
    /// This is ESPN-shaped (never 0); `CFBWeekCalendar.resolve` maps it onto Pickems weeks.
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

    static func makeWeekSummary(
        id: String,
        info: CFBWeekInfo,
        rules: GroupRules,
        memberCount: Int,
        now: Date = Date()
    ) -> WeekSummary {
        let parsed = parseWeekId(id)
        let seasonYear = parsed?.seasonYear ?? info.seasonYear
        let weekNumber = parsed?.weekNumber ?? CFBWeekCalendar.resolve(espn: info, now: now).weekNumber
        let isFixed = weekNumber == 0
        return WeekSummary(
            id: id,
            seasonYear: seasonYear,
            weekNumber: weekNumber,
            status: isFixed ? .picking : .selection,
            slateSize: isFixed ? 8 : rules.expectedSlateSize(memberCount: memberCount),
            selectionMode: rules.selectionMode,
            selectionsPerMember: rules.selectionsPerMember,
            lockedAt: isFixed ? now : nil,
            pickDeadline: nil,
            nominationCount: 0,
            selectionDeadline: nil,
            selectionDeadlineSetAt: nil,
            selectionDeadlineSetBy: nil,
            slateSource: isFixed ? CFBWeekCalendar.weekZeroSlateSource : nil
        )
    }

    private static func resolvedFallback(on date: Date) -> CFBAppWeek {
        let year = CFBSeasonCalendar.seasonYear(containing: date)
        let info = CFBWeekInfo(
            seasonYear: year,
            weekNumber: estimatedCFBWeek(on: date),
            seasonType: 2,
            label: ""
        )
        return CFBWeekCalendar.resolve(espn: info, now: date)
    }
}
