import Foundation

/// Postseason bowl weeks. Keep in sync with `firebase/functions/src/bowlWeek.ts`.
enum CFBBowlSeason {
    static let postseasonSeasonType = 3
    static let espnPostseasonWeek = 1
    static let userFacingBowlWeekName = "Bowl Bonanza"
    static let bowlCatalogSlateSource = "bowlCatalog"

    enum Slot: String, Codable, CaseIterable, Identifiable {
        case bowl1 = "BOWL1"
        case bowl2 = "BOWL2"
        /// Mode B: every postseason bowl in one `2026-BOWL` week.
        case bowlAll = "BOWL"

        var id: String { rawValue }

        var pickemsWeekNumber: Int {
            switch self {
            case .bowl1, .bowlAll: return 1
            case .bowl2: return 2
            }
        }

        var espnWeekNumber: Int {
            switch self {
            case .bowl1, .bowlAll: return 1
            case .bowl2: return 999
            }
        }

        var chipDateRange: String {
            switch self {
            case .bowl1: return "Dec 12-Jan 1"
            case .bowl2: return "Jan 2-Jan 25"
            case .bowlAll: return "Dec 13-Jan 25"
            }
        }

        var catalogEndExclusive: Date {
            switch self {
            case .bowl1:
                return easternDate(year: 2027, month: 1, day: 2) ?? .distantFuture
            case .bowl2, .bowlAll:
                return easternDate(year: 2027, month: 1, day: 26) ?? .distantFuture
            }
        }
    }

    enum Mode: String, Codable, CaseIterable, Identifiable {
        case modeA
        case modeB

        var id: String { rawValue }

        /// Commissioner-facing label (never "Mode A/B").
        var commissionerLabel: String {
            switch self {
            case .modeA: return "Pick bowl games"
            case .modeB: return "Every bowl game"
            }
        }
    }

    struct Settings: Codable, Equatable {
        var mode: Mode
        var isEnabled: Bool
        var pickCount: Int?
        var countsTowardSeasonStandings: Bool
        /// Mode A only: mint `2026-BOWL2` for NY6 & CFP cluster.
        var includesSecondWeek: Bool
        var suggestedRollingLock: Bool

        static let `default` = Settings(
            mode: .modeA,
            isEnabled: true,
            pickCount: nil,
            countsTowardSeasonStandings: false,
            includesSecondWeek: false,
            suggestedRollingLock: true
        )

        var isConfigured: Bool { isEnabled }

        var isModeB: Bool { isEnabled && mode == .modeB }

        static func resolved(from rules: GroupRules) -> Settings {
            rules.bowlSeason ?? .default
        }

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

    static func isBowlFullSlateWeek(_ week: WeekSummary) -> Bool {
        week.bowlFullSlate == true || week.slateSource == bowlCatalogSlateSource
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

    static func canonicalSeasonYear(containing date: Date = Date()) -> Int {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let year = eastern.component(.year, from: date)
        let month = eastern.component(.month, from: date)
        if year == 2027, month == 1 { return 2026 }
        return year
    }

    static func catalogOpens(year: Int = 2026) -> Date {
        easternDate(year: year, month: 12, day: 6, hour: 15) ?? .distantPast
    }

    static func belongsToBowlSlot(kickoff: Date, slot: Slot, fromEspnPostseasonWeek: Int) -> Bool {
        guard kickoff >= catalogOpens() else { return false }
        if slot == .bowlAll {
            return fromEspnPostseasonWeek == Slot.bowl1.espnWeekNumber
                || fromEspnPostseasonWeek == Slot.bowl2.espnWeekNumber
        }
        let cutoff = Slot.bowl1.catalogEndExclusive
        if fromEspnPostseasonWeek == Slot.bowl2.espnWeekNumber {
            return slot == .bowl2
        }
        guard fromEspnPostseasonWeek == Slot.bowl1.espnWeekNumber else { return false }
        return slot == .bowl1 ? kickoff < cutoff : kickoff >= cutoff
    }

    static func catalogEligible(kickoff: Date, week: WeekSummary? = nil, now: Date = Date()) -> Bool {
        guard kickoff >= catalogOpens() else { return false }
        guard let slot = week.flatMap({ slot(for: $0) }) else { return true }
        switch slot {
        case .bowlAll:
            return true
        case .bowl1:
            return belongsToBowlSlot(
                kickoff: kickoff,
                slot: .bowl1,
                fromEspnPostseasonWeek: Slot.bowl1.espnWeekNumber
            )
        case .bowl2:
            return belongsToBowlSlot(
                kickoff: kickoff,
                slot: .bowl2,
                fromEspnPostseasonWeek: Slot.bowl1.espnWeekNumber
            ) || belongsToBowlSlot(
                kickoff: kickoff,
                slot: .bowl2,
                fromEspnPostseasonWeek: Slot.bowl2.espnWeekNumber
            )
        }
    }

    static func catalogEligible(
        game: ESPNGame,
        week: WeekSummary? = nil,
        fromEspnPostseasonWeek: Int,
        now: Date = Date()
    ) -> Bool {
        guard let slot = week.flatMap({ slot(for: $0) }) else {
            return game.kickoff >= catalogOpens()
        }
        return belongsToBowlSlot(
            kickoff: game.kickoff,
            slot: slot,
            fromEspnPostseasonWeek: fromEspnPostseasonWeek
        )
    }

    static func standingsToggleLocked(weeks: [WeekSummary]) -> Bool {
        weeks.contains { isBowlWeek($0) && $0.status == .scored }
    }

    static func calendarSlots(seasonYear: Int, settings: Settings) -> [CFBSeasonWeek] {
        guard settings.isConfigured, seasonYear == 2026 else { return [] }
        if settings.mode == .modeB {
            return [.seasonWeek(seasonYear: seasonYear, slot: .bowlAll)]
        }
        var slots: [CFBSeasonWeek] = [.seasonWeek(seasonYear: seasonYear, slot: .bowl1)]
        if settings.includesSecondWeek {
            slots.append(.seasonWeek(seasonYear: seasonYear, slot: .bowl2))
        }
        return slots
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
        let modeB = settings.mode == .modeB
        var week = WeekSummary(
            id: id,
            seasonYear: seasonYear,
            weekNumber: slot.pickemsWeekNumber,
            status: .selection,
            slateSize: modeB ? 1 : settings.resolvedPickCount(rules: rules),
            selectionMode: .commissioner,
            selectionsPerMember: rules.selectionsPerMember,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0,
            selectionDeadline: nil,
            selectionDeadlineSetAt: nil,
            selectionDeadlineSetBy: nil,
            slateSource: modeB ? bowlCatalogSlateSource : nil,
            bowlFullSlate: modeB ? true : nil,
            seasonType: postseasonSeasonType,
            bowlSlot: slot.rawValue
        )
        week.pickLockMode = .rolling
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