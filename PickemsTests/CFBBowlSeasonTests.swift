import Foundation
import Testing
@testable import Pickems

struct CFBBowlSeasonTests {
    @Test func bowlWeekIdRoundTrip() {
        let id = CFBBowlSeason.weekId(seasonYear: 2026, slot: .bowl1)
        #expect(id == "2026-BOWL1")
        let parsed = CFBBowlSeason.parseWeekId(id)
        #expect(parsed?.seasonYear == 2026)
        #expect(parsed?.slot == .bowl1)
    }

    @Test func parseWeekIdBowlViaSync() {
        let parsed = CFBWeekSync.parseWeekId("2026-BOWL2")
        #expect(parsed?.seasonYear == 2026)
        #expect(parsed?.weekNumber == CFBBowlSeason.Slot.bowl2.pickemsWeekNumber)
    }

    @Test func postseasonEspnResolvesToBowlIdNotW1() {
        let info = CFBWeekInfo(seasonYear: 2026, weekNumber: 1, seasonType: 3, label: "")
        let app = CFBWeekCalendar.resolve(espn: info)
        #expect(app.id == "2026-BOWL1")
        #expect(app.seasonType == 3)
    }

    @Test func chipLabelIsBowlBonanza() {
        let week = WeekSummary(
            id: "2026-BOWL1",
            seasonYear: 2026,
            weekNumber: 1,
            status: .selection,
            slateSize: 12,
            selectionMode: .commissioner,
            selectionsPerMember: 1,
            nominationCount: 0,
            seasonType: 3,
            bowlSlot: "BOWL1"
        )
        #expect(CFBBowlSeason.chipPrimaryLabel(for: week) == "Bowl Bonanza")
        #expect(week.displayLabel == "Season 2026 | Bowl Bonanza")
        #expect(CFBBowlSeason.userFacingWeekName(for: week) == "Bowl Bonanza")
    }

    @Test func januaryStaysSeason2026() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let jan = eastern.date(from: DateComponents(year: 2027, month: 1, day: 15))!
        #expect(CFBBowlSeason.canonicalSeasonYear(containing: jan) == 2026)
        #expect(CFBSeasonCalendar.seasonYear(containing: jan) == 2026)
    }

    @Test func bowlCalendarSlotsOnlyWhenEnabled() {
        var rules = GroupRules.default
        #expect(CFBBowlSeason.calendarSlots(seasonYear: 2026, settings: rules.bowlSeason ?? .default).isEmpty)
        rules.bowlSeason = CFBBowlSeason.Settings(
            mode: .modeA,
            isEnabled: true,
            pickCount: 8,
            countsTowardSeasonStandings: false,
            includesSecondWeek: true,
            suggestedRollingLock: true
        )
        let slots = CFBBowlSeason.calendarSlots(seasonYear: 2026, settings: rules.bowlSeason!)
        #expect(slots.count == 2)
        #expect(slots.map(\.id) == ["2026-BOWL1", "2026-BOWL2"])
    }

    @Test func settingsDefaultPickCountUsesSlateSize() {
        var rules = GroupRules.default
        rules.slateSize = 10
        rules.bowlSeason = .default
        #expect(rules.bowlSeason!.resolvedPickCount(rules: rules) == 10)
    }

    @Test func leaderboardShowsBowlScopeWhenConfigured() {
        var rules = GroupRules.default
        rules.bowlSeason = CFBBowlSeason.Settings(
            mode: .modeA,
            isEnabled: true,
            pickCount: 12,
            countsTowardSeasonStandings: false,
            includesSecondWeek: false,
            suggestedRollingLock: true
        )
        #expect(LeaderboardScope.showsBowlScope(rules: rules))
    }

    @Test func commissionerBlockAvailableWeek14() {
        #expect(CFBBowlSeason.commissionerSettingsAvailable(pickemsWeekNumber: 14, espnSeasonType: 2))
        #expect(!CFBBowlSeason.commissionerSettingsAvailable(pickemsWeekNumber: 13, espnSeasonType: 2, now: Date(timeIntervalSince1970: 1_000_000)))
    }

    @Test func bowlSlotsPartitionPostseasonWeekOneGames() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let early = eastern.date(from: DateComponents(year: 2026, month: 12, day: 20))!
        let late = eastern.date(from: DateComponents(year: 2027, month: 1, day: 10))!
        #expect(CFBBowlSeason.belongsToBowlSlot(
            kickoff: early,
            slot: .bowl1,
            fromEspnPostseasonWeek: 1
        ))
        #expect(!CFBBowlSeason.belongsToBowlSlot(
            kickoff: late,
            slot: .bowl1,
            fromEspnPostseasonWeek: 1
        ))
        #expect(CFBBowlSeason.belongsToBowlSlot(
            kickoff: late,
            slot: .bowl2,
            fromEspnPostseasonWeek: 1
        ))
        #expect(CFBBowlSeason.belongsToBowlSlot(
            kickoff: late,
            slot: .bowl2,
            fromEspnPostseasonWeek: 999
        ))
    }

    @Test func bowl1CatalogExcludesJanuaryAfterEndExclusive() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let jan = eastern.date(from: DateComponents(year: 2027, month: 1, day: 10))!
        let dec = eastern.date(from: DateComponents(year: 2026, month: 12, day: 20))!
        let bowl1 = WeekSummary(
            id: "2026-BOWL1",
            seasonYear: 2026,
            weekNumber: 1,
            status: .selection,
            slateSize: 8,
            selectionMode: .commissioner,
            selectionsPerMember: 1,
            nominationCount: 0,
            seasonType: 3,
            bowlSlot: "BOWL1"
        )
        #expect(CFBBowlSeason.catalogEligible(kickoff: dec, week: bowl1))
        #expect(!CFBBowlSeason.catalogEligible(kickoff: jan, week: bowl1))
    }

    @Test func standingsToggleLockedAfterScoredBowl() {
        let scored = WeekSummary(
            id: "2026-BOWL1",
            seasonYear: 2026,
            weekNumber: 1,
            status: .scored,
            slateSize: 8,
            selectionMode: .commissioner,
            selectionsPerMember: 1,
            nominationCount: 0,
            seasonType: 3,
            bowlSlot: "BOWL1"
        )
        #expect(CFBBowlSeason.standingsToggleLocked(weeks: [scored]))
        #expect(!CFBBowlSeason.standingsToggleLocked(weeks: []))
    }
}