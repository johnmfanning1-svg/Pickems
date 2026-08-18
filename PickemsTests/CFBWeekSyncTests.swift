import Foundation
import Testing
@testable import Pickems

struct CFBWeekSyncTests {
    @Test func weekIdFormatsSeasonYearAndWeekNumber() {
        let info = CFBWeekInfo(
            seasonYear: 2026,
            weekNumber: 3,
            seasonType: 2,
            label: "Season 2026 | Week 3"
        )
        #expect(CFBWeekSync.weekId(for: info) == "2026-W3")
    }

    @Test func estimatedWeekIsOneBeforeKickoff() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!

        let beforeKickoff = eastern.date(from: DateComponents(
            year: 2026, month: 8, day: 26, hour: 12
        ))!
        #expect(CFBWeekSync.estimatedCFBWeek(on: beforeKickoff) == 1)
    }

    @Test func estimatedWeekIsOneAtKickoff() {
        let kickoff = CFBSeasonCalendar.seasonKickoff(forSeasonYear: 2026)
        #expect(CFBWeekSync.estimatedCFBWeek(on: kickoff) == 1)
    }

    @Test func estimatedWeekMatchesTwoWeeksAfterKickoff() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!

        let kickoff = CFBSeasonCalendar.seasonKickoff(forSeasonYear: 2026)
        let twoWeeksLater = eastern.date(byAdding: .day, value: 14, to: kickoff)!
        #expect(CFBWeekSync.estimatedCFBWeek(on: twoWeeksLater) == 3)
    }

    @Test func fallbackPrefersLastKnownWeekOverEstimate() {
        let suite = "pickems.tests.cfbWeekSync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let info = CFBWeekInfo(
            seasonYear: 2026,
            weekNumber: 2,
            seasonType: 2,
            label: "Season 2026 | Week 2"
        )
        CFBWeekSync.persistLastKnownWeek(info, defaults: defaults)

        // Cold estimate for a date far from kickoff would disagree; last-known must win.
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let lateSeason = eastern.date(from: DateComponents(
            year: 2026, month: 11, day: 15, hour: 12
        ))!

        #expect(CFBWeekSync.fallbackWeekId(defaults: defaults, on: lateSeason) == "2026-W2")
        #expect(CFBWeekSync.estimatedCFBWeek(on: lateSeason) != 2)
    }

    @Test func fallbackUsesEstimateWhenCacheCold() {
        let suite = "pickems.tests.cfbWeekSync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let beforeKickoff = eastern.date(from: DateComponents(
            year: 2026, month: 8, day: 1, hour: 12
        ))!

        #expect(CFBWeekSync.fallbackWeekId(defaults: defaults, on: beforeKickoff) == "2026-W0")
    }

    @Test func fallbackOverridesStaleWeek1CacheDuringWeekZeroWindow() {
        let suite = "pickems.tests.cfbWeekSync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("2026-W1", forKey: CFBWeekSync.lastKnownWeekIdKey)

        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let duringWindow = eastern.date(from: DateComponents(
            year: 2026, month: 8, day: 18, hour: 12
        ))!

        #expect(CFBWeekSync.fallbackWeekId(defaults: defaults, on: duringWindow) == "2026-W0")
    }

    @Test func parseWeekIdReadsYearAndNumber() {
        #expect(CFBWeekSync.parseWeekId("2026-W0")?.seasonYear == 2026)
        #expect(CFBWeekSync.parseWeekId("2026-W0")?.weekNumber == 0)
        #expect(CFBWeekSync.parseWeekId("2026-W15")?.weekNumber == 15)
        #expect(CFBWeekSync.parseWeekId("nope") == nil)
    }

    @Test func makeWeekSummaryHonorsRequestedWeekOneDuringWeekZeroWindow() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let duringWindow = eastern.date(from: DateComponents(
            year: 2026, month: 8, day: 18, hour: 12
        ))!
        let info = CFBWeekInfo(seasonYear: 2026, weekNumber: 1, seasonType: 2, label: "")
        let week = CFBWeekSync.makeWeekSummary(
            id: "2026-W1",
            info: info,
            rules: .default,
            memberCount: 3,
            now: duringWindow
        )
        #expect(week.weekNumber == 1)
        #expect(week.status == .selection)
        #expect(week.skipsSelection == false)
    }
}
