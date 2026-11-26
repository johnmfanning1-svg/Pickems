import Foundation
import Testing
@testable import Pickems

struct DefaultSelectionLockTests {
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

    @Test func pastInstantStillReturned() {
        let lock = DefaultSelectionLock(enabled: true, weekday: 1, hour: 9, minute: 0, timeZone: "America/New_York")
        let deadline = DefaultSelectionLockMath.deadline(for: lock, seasonYear: 2026, weekNumber: 1)
        #expect(deadline != nil)
        #expect(deadline! < Date())
    }

    @Test func makeWeekSummaryStampsDefaultWhenEnabled() {
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
            memberCount: 4
        )
        #expect(week.selectionDeadline != nil)
        #expect(week.selectionDeadlineSetBy == DefaultSelectionLockStamp.setBy)
    }

    @Test func makeWeekSummaryDoesNotOverwriteStampLogicOnWeekZero() {
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
            memberCount: 4
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
        DefaultSelectionLockStamp.apply(to: &week, lock: lock)
        #expect(week.selectionDeadlineSetBy == "commish")
    }
}