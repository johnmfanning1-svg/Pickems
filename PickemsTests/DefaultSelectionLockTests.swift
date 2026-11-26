import Foundation
import Testing
@testable import Pickems

struct DefaultSelectionLockTests {
    private static let beforeSep16 = {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        return eastern.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!
    }()

    @Test func decodesDefaultSelectionLockFromRules() throws {
        let json = Data(#"""
        {
          "selectionMode": "member",
          "selectionsPerMember": 3,
          "slateSize": 12,
          "pickDeadline": "firstKickoff",
          "tieBreaker": "commissionerOverride",
          "defaultSelectionLock": {
            "enabled": true,
            "weekday": 3,
            "hour": 23,
            "minute": 59,
            "timeZone": "America/New_York"
          }
        }
        """#.utf8)
        let rules = try JSONDecoder().decode(GroupRules.self, from: json)
        #expect(rules.defaultSelectionLock?.enabled == true)
        #expect(rules.defaultSelectionLock?.weekday == 3)
    }

    @Test func wednesdayInside2026Week3Window() {
        let lock = DefaultSelectionLock(enabled: true, weekday: 3, hour: 23, minute: 59, timeZone: "America/New_York")
        let deadline = DefaultSelectionLockMath.deadline(for: lock, seasonYear: 2026, weekNumber: 3)
        #expect(deadline != nil)
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let parts = eastern.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: deadline!)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 16)
        #expect(parts.hour == 23)
        #expect(parts.minute == 59)
        #expect(DefaultSelectionLockMath.isoWeekday(from: parts.weekday!) == 3)
    }

    @Test func week1HasNoWednesdayForDefault() {
        let lock = DefaultSelectionLock(enabled: true, weekday: 3, hour: 23, minute: 59, timeZone: "America/New_York")
        #expect(DefaultSelectionLockMath.deadline(for: lock, seasonYear: 2026, weekNumber: 1) == nil)
    }

    @Test func dstEarlyNovemberUsesLockZone() {
        let lock = DefaultSelectionLock(enabled: true, weekday: 2, hour: 18, minute: 0, timeZone: "America/New_York")
        let deadline = DefaultSelectionLockMath.deadline(for: lock, seasonYear: 2026, weekNumber: 10)
        #expect(deadline != nil)
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let parts = eastern.dateComponents([.month, .day, .hour], from: deadline!)
        #expect(parts.month == 11)
        #expect(parts.day == 3)
        #expect(parts.hour == 18)
    }

    @Test func pacificLockOnEasternWeekWindow() {
        let lock = DefaultSelectionLock(enabled: true, weekday: 4, hour: 19, minute: 0, timeZone: "America/Los_Angeles")
        let deadline = DefaultSelectionLockMath.deadline(for: lock, seasonYear: 2026, weekNumber: 2)
        #expect(deadline != nil)
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let parts = pacific.dateComponents([.weekday, .hour], from: deadline!)
        #expect(DefaultSelectionLockMath.isoWeekday(from: parts.weekday!) == 4)
        #expect(parts.hour == 19)
    }

    @Test func pastInstantDoesNotStampFuturePath() {
        let lock = DefaultSelectionLock(enabled: true, weekday: 3, hour: 23, minute: 59, timeZone: "America/New_York")
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let after = eastern.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 0))!
        #expect(DefaultSelectionLockMath.futureDeadline(
            for: lock,
            seasonYear: 2026,
            weekNumber: 3,
            now: after
        ) == nil)
    }

    @Test func makeWeekSummaryStampsDefaultWhenEnabledAndFuture() {
        var rules = GroupRules.default
        var lock = DefaultSelectionLock.disabled
        lock.enabled = true
        lock.weekday = 3
        lock.hour = 20
        lock.minute = 0
        rules.defaultSelectionLock = lock
        let week = CFBWeekSync.makeWeekSummary(
            id: "2026-W3",
            info: CFBWeekInfo(seasonYear: 2026, weekNumber: 3, seasonType: 2, label: ""),
            rules: rules,
            memberCount: 4,
            now: Self.beforeSep16
        )
        #expect(week.selectionDeadline != nil)
        #expect(week.selectionDeadlineSetBy == DefaultSelectionLockStamp.setBy)
    }

    @Test func makeWeekSummarySkipsPastDefaultAtMint() {
        var rules = GroupRules.default
        rules.defaultSelectionLock = DefaultSelectionLock(
            enabled: true,
            weekday: 3,
            hour: 23,
            minute: 59,
            timeZone: "America/New_York"
        )
        let week = CFBWeekSync.makeWeekSummary(
            id: "2026-W3",
            info: CFBWeekInfo(seasonYear: 2026, weekNumber: 3, seasonType: 2, label: ""),
            rules: rules,
            memberCount: 4,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(week.selectionDeadline == nil)
    }

    @Test func makeWeekSummaryDoesNotStampWeekZero() {
        var rules = GroupRules.default
        rules.defaultSelectionLock = DefaultSelectionLock(
            enabled: true,
            weekday: 3,
            hour: 23,
            minute: 59,
            timeZone: "America/New_York"
        )
        let week = CFBWeekSync.makeWeekSummary(
            id: "2026-W0",
            info: CFBWeekInfo(seasonYear: 2026, weekNumber: 1, seasonType: 2, label: ""),
            rules: rules,
            memberCount: 4,
            now: Self.beforeSep16
        )
        #expect(week.skipsSelection)
        #expect(week.selectionDeadline == nil)
    }

    @Test func stampSkipsWhenDeadlineAlreadySet() {
        var week = WeekSummary(
            id: "2026-W3",
            seasonYear: 2026,
            weekNumber: 3,
            status: .selection,
            slateSize: 12,
            selectionMode: .member,
            selectionsPerMember: 3,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0,
            selectionDeadline: Date(timeIntervalSince1970: 1),
            selectionDeadlineSetAt: Date(),
            selectionDeadlineSetBy: "commish"
        )
        let lock = DefaultSelectionLock(enabled: true, weekday: 3, hour: 23, minute: 59, timeZone: "America/New_York")
        DefaultSelectionLockStamp.apply(to: &week, lock: lock, stampedAt: Self.beforeSep16)
        #expect(week.selectionDeadlineSetBy == "commish")
    }

    @Test func rulesSaveStampCandidatesCoversMultipleSelectionWeeks() {
        var rules = GroupRules.default
        let lock = DefaultSelectionLock(
            enabled: true,
            weekday: 4,
            hour: 19,
            minute: 0,
            timeZone: "America/New_York"
        )
        rules.defaultSelectionLock = lock
        let current = selectionWeek(weekNumber: 6)
        let upcoming = selectionWeek(weekNumber: 14)
        let stamped = selectionWeek(
            weekNumber: 7,
            selectionDeadline: Date(timeIntervalSince1970: 1),
            selectionDeadlineSetBy: "commish"
        )
        let skipWeekZero = weekZeroMintedAsPicking()
        let targets = DefaultSelectionLockRulesSave.weeksToStamp(
            among: [current, upcoming, stamped, skipWeekZero],
            lock: lock,
            rules: rules,
            now: Self.beforeSep16
        )
        let ids = Set(targets.map { $0.week.id })
        #expect(ids == Set(["2026-W6", "2026-W14"]))
        #expect(targets.allSatisfy { $0.week.selectionDeadlineSetBy == nil })
    }

    @Test func rulesSaveStampCandidatesSkipPastInstant() {
        var rules = GroupRules.default
        let lock = DefaultSelectionLock(
            enabled: true,
            weekday: 3,
            hour: 23,
            minute: 59,
            timeZone: "America/New_York"
        )
        rules.defaultSelectionLock = lock
        let week = selectionWeek(weekNumber: 3)
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let after = eastern.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 0))!
        #expect(DefaultSelectionLockRulesSave.weeksToStamp(
            among: [week],
            lock: lock,
            rules: rules,
            now: after
        ).isEmpty)
    }

    @Test func rulesSaveStampCandidatesSkipSkipsSelection() {
        var rules = GroupRules.default
        rules.defaultSelectionLock = DefaultSelectionLock(
            enabled: true,
            weekday: 3,
            hour: 23,
            minute: 59,
            timeZone: "America/New_York"
        )
        let week = weekZeroMintedAsPicking()
        #expect(week.skipsSelection)
        #expect(DefaultSelectionLockRulesSave.weeksToStamp(
            among: [week],
            lock: rules.defaultSelectionLock!,
            rules: rules,
            now: Self.beforeSep16
        ).isEmpty)
    }

    private func selectionWeek(
        weekNumber: Int,
        selectionDeadline: Date? = nil,
        selectionDeadlineSetBy: String? = nil
    ) -> WeekSummary {
        WeekSummary(
            id: "2026-W\(weekNumber)",
            seasonYear: 2026,
            weekNumber: weekNumber,
            status: .selection,
            slateSize: 12,
            selectionMode: .member,
            selectionsPerMember: 3,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0,
            selectionDeadline: selectionDeadline,
            selectionDeadlineSetAt: selectionDeadline == nil ? nil : Date(),
            selectionDeadlineSetBy: selectionDeadlineSetBy
        )
    }

    private func weekZeroMintedAsPicking() -> WeekSummary {
        WeekSummary(
            id: "2026-W0",
            seasonYear: 2026,
            weekNumber: 0,
            status: .selection,
            slateSize: 12,
            selectionMode: .member,
            selectionsPerMember: 3,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0,
            slateSource: CFBWeekCalendar.weekZeroSlateSource
        )
    }

    @Test func parityThursdayTableMatchesTypeScriptWeeks() {
        let lock = DefaultSelectionLock(enabled: true, weekday: 4, hour: 19, minute: 0, timeZone: "America/New_York")
        let cases: [(Int, Int, Int)] = [
            (1, 9, 3),
            (2, 9, 10),
            (3, 9, 17),
            (10, 11, 5),
            (15, 12, 10),
        ]
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        for (weekNumber, month, day) in cases {
            guard let d = DefaultSelectionLockMath.deadline(for: lock, seasonYear: 2026, weekNumber: weekNumber) else {
                Issue.record("missing deadline for week \(weekNumber)")
                continue
            }
            let parts = eastern.dateComponents([.month, .day, .hour], from: d)
            #expect(parts.month == month)
            #expect(parts.day == day)
            #expect(parts.hour == 19)
        }
        #expect(DefaultSelectionLockMath.deadline(for: lock, seasonYear: 2026, weekNumber: 0) == nil)
    }
}