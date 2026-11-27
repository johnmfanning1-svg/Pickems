import Foundation

/// Postseason bowl weeks (Mode A: pick X games). Keep in sync with `firebase/functions/src/bowlWeek.ts`.
enum CFBBowlSeason {
    static let postseasonSeasonType = 3
    static let espnPostseasonWeek = 1
    /// User-facing name for bowl pick weeks (`2026-BOWL1` / `BOWL2` doc ids unchanged).
    static let userFacingBowlWeekName = "Bowl Bonanza"

    enum Slot: String, Codable, CaseIterable, Identifiable {
        case bowl1 = "BOWL1"
        case bowl2 = "BOWL2"

        var id: String { rawValue }

        /// Stored on `weeks/{id}.weekNumber` — mirrors ESPN postseason week numbers (1 / 999 → 1 / 2).
        var pickemsWeekNumber: Int {
            switch self {
            case .bowl1: return 1
            case .bowl2: return 2
            }
        }

        var espnWeekNumber: Int {
            switch self {
            case .bowl1: return 1
            case .bowl2: return 999
            }
        }

        var chipDateRange: String {
            switch self {
            case .bowl1: return "Dec 12-Jan 1"
            case .bowl2: return "Jan 2-Jan 25"
            }
        }

        var catalogEndExclusive: Date {
            switch self {
            case .bowl1:
                return easternDate(year: 2027, month: 1, day: 2) ?? .distantFuture
            case .bowl2:
                return easternDate(year: 2027, month: 1, day: 26) ?? .distantFuture
            }
        }
    }

    enum Mode: String, Codable {
        case modeA
        /// Reserved for a future all-bowls week. Not exposed in commissioner UI yet.
        case modeB
    }

    struct Settings: Codable, Equatable {
        var mode: Mode
        /// When false, bowl weeks stay off the chip bar until the commissioner enables them.
        var isEnabled: Bool
        /// Target bowl games (defaults to league `slateSize`). Hard-capped at 20 in rules.
        var pickCount: Int?
        /// When true, scored bowl weeks update `seasonWins` / `seasonLosses`. Default false.
        var countsTowardSeasonStandings: Bool
        /// Mint `2026-BOWL2` for late December / CFP cluster.
        var includesSecondWeek: Bool
        /// Mode A default: rolling lock is the recommended postseason policy.
        var suggestedRollingLock: Bool

        static let `default` = Settings(
            mode: .modeA,
            isEnabled: false,
            pickCount: nil,
            countsTowardSeasonStandings: false,
            includesSecondWeek: false,
            suggestedRollingLock: true
        )

        var isConfigured: Bool { isEnabled && mode == .modeA }

        func resolvedPickCount(rules: GroupRules) -> Int {
            min(20, max(1, pickCount ?? rules.slateSize))
        }
    }

    static func weekId(seasonYear: Int, slot: Slot) -> String {
        "\(seasonYear)-\(slot.rawValue)"
    }

    static func parseWeekId(_ id: String) -> (seasonYear: Int, slot: Slot)? {
        let parts = id.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let year = Int(parts[0]) else { return nil }
        guard let slot = Slot(rawValue: String(parts[1])) else { return nil }
        return (year, slot)
    }

    static func isBowlWeekId(_ id: String) -> Bool {
        parseWeekId(id) != nil
    }

    static func slot(for week: WeekSummary) -> Slot? {
        if let encoded = week.bowlSlot, let slot = Slot(rawValue: encoded) {
            return slot
        }
        return parseWeekId(week.id)?.slot
    }

    static func isBowlWeek(_ week: WeekSummary) -> Bool {
        week.seasonType == postseasonSeasonType || isBowlWeekId(week.id)
    }

    static func userFacingWeekName(for week: WeekSummary) -> String {
        isBowlWeek(week) ? userFacingBowlWeekName : "Week \(week.weekNumber)"
    }

    static func chipPrimaryLabel(for week: WeekSummary) -> String {
        userFacingWeekName(for: week)
    }

    static func displayLabel(for week: WeekSummary) -> String {
        "Season \(week.seasonYear.pickemsYearString) | \(userFacingWeekName(for: week))"
    }

    /// Keep CFB season year on 2026 through January bowl games.
    static func canonicalSeasonYear(containing date: Date = Date()) -> Int {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let year = eastern.component(.year, from: date)
        let month = eastern.component(.month, from: date)
        if year == 2027, month == 1 { return 2026 }
        return year
    }

    /// Selection Sunday — postseason catalog opens for bowl slates.
    static func catalogOpens(year: Int = 2026) -> Date {
        easternDate(year: year, month: 12, day: 6, hour: 15) ?? .distantPast
    }

    static func catalogEligible(kickoff: Date, now: Date = Date()) -> Bool {
        kickoff >= catalogOpens()
    }

    static func catalogEligible(game: ESPNGame, now: Date = Date()) -> Bool {
        catalogEligible(kickoff: game.kickoff, now: now)
    }

    /// Commissioner Bowl block unlocks once regular-season Week 14 is underway.
    static func commissionerSettingsAvailable(
        pickemsWeekNumber: Int?,
        espnSeasonType: Int?,
        now: Date = Date()
    ) -> Bool {
        if espnSeasonType == postseasonSeasonType { return true }
        if let week = pickemsWeekNumber, week >= 14 { return true }
        return now >= easternDate(year: 2026, month: 11, day: 30) ?? .distantFuture
    }

    static func calendarSlots(seasonYear: Int, settings: Settings) -> [CFBSeasonWeek] {
        guard settings.isConfigured, seasonYear == 2026 else { return [] }
        var slots: [CFBSeasonWeek] = [.seasonWeek(seasonYear: seasonYear, slot: .bowl1)]
        if settings.includesSecondWeek {
            slots.append(.seasonWeek(seasonYear: seasonYear, slot: .bowl2))
        }
        return slots
    }

    static func resolvedPostseasonWeekId(seasonYear: Int, settings: Settings) -> String {
        weekId(seasonYear: seasonYear, slot: .bowl1)
    }

    static func makeWeekSummary(
        id: String,
        slot: Slot,
        rules: GroupRules,
        memberCount: Int,
        now: Date = Date()
    ) -> WeekSummary {
        let parsed = parseWeekId(id)
        let seasonYear = parsed?.seasonYear ?? canonicalSeasonYear(containing: now)
        let settings = rules.bowlSeason ?? .default
        var week = WeekSummary(
            id: id,
            seasonYear: seasonYear,
            weekNumber: slot.pickemsWeekNumber,
            status: .selection,
            slateSize: settings.resolvedPickCount(rules: rules),
            selectionMode: rules.selectionMode,
            selectionsPerMember: rules.selectionsPerMember,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0,
            selectionDeadline: nil,
            selectionDeadlineSetAt: nil,
            selectionDeadlineSetBy: nil,
            seasonType: postseasonSeasonType,
            bowlSlot: slot.rawValue
        )
        if rules.bowlSeason?.suggestedRollingLock == true {
            week.pickLockMode = .rolling
        }
        if let lock = rules.defaultSelectionLock {
            DefaultSelectionLockStamp.apply(to: &week, lock: lock, stampedAt: now)
        }
        return week
    }

    static func compareWeekOrder(_ lhs: WeekSummary, _ rhs: WeekSummary) -> Bool {
        if lhs.seasonYear != rhs.seasonYear { return lhs.seasonYear < rhs.seasonYear }
        let lhsBowl = isBowlWeek(lhs)
        let rhsBowl = isBowlWeek(rhs)
        if lhsBowl != rhsBowl { return !lhsBowl && rhsBowl }
        if lhsBowl { return lhs.id < rhs.id }
        return lhs.weekNumber < rhs.weekNumber
    }

    static func espnScoreboardWeek(for week: WeekSummary) -> Int {
        if let slot = slot(for: week) { return slot.espnWeekNumber }
        return CFBWeekCalendar.espnScoreboardWeek(week.weekNumber)
    }

    static func espnSeasonType(for week: WeekSummary) -> Int {
        week.seasonType ?? (isBowlWeek(week) ? postseasonSeasonType : 2)
    }

    private static func easternDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date? {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return eastern.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }
}

private extension CFBSeasonWeek {
    static func seasonWeek(seasonYear: Int, slot: CFBBowlSeason.Slot) -> CFBSeasonWeek {
        CFBSeasonWeek(
            seasonYear: seasonYear,
            weekNumber: slot.pickemsWeekNumber,
            espnWeekNumber: slot.espnWeekNumber,
            dateRangeLabel: slot.chipDateRange,
            pickemsWeekId: CFBBowlSeason.weekId(seasonYear: seasonYear, slot: slot)
        )
    }
}