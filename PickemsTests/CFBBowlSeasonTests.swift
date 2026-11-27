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

    @Test func bowlCalendarSlotsDefaultOnWhenRulesMissing() {
        let rules = GroupRules.default
        #expect(rules.bowlSeason == nil)
        let slots = CFBBowlSeason.calendarSlots(
            seasonYear: 2026,
            settings: CFBBowlSeason.Settings.resolved(from: rules)
        )
        #expect(slots.count == 1)
        #expect(slots.map(\.id) == ["2026-BOWL1"])
        #expect(CFBBowlSeason.userFacingBowlWeekName == "Bowl Bonanza")
    }

    @Test func bowlCalendarSlotsEmptyWhenCommissionerTurnsOff() {
        var rules = GroupRules.default
        rules.bowlSeason = CFBBowlSeason.Settings(
            mode: .modeA,
            isEnabled: false,
            pickCount: nil,
            countsTowardSeasonStandings: false,
            includesSecondWeek: false,
            suggestedRollingLock: true
        )
        let slots = CFBBowlSeason.calendarSlots(
            seasonYear: 2026,
            settings: CFBBowlSeason.Settings.resolved(from: rules)
        )
        #expect(slots.isEmpty)
    }

    @Test func bowlCalendarSlotsIncludeSecondWeekOnlyWhenOptIn() {
        var rules = GroupRules.default
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

    @Test func bowlWheelOrderPutsBowl1AfterWeekFifteen() {
        let w15 = WeekSummary(
            id: "2026-W15",
            seasonYear: 2026,
            weekNumber: 15,
            status: .selection,
            slateSize: 10,
            selectionMode: .commissioner,
            selectionsPerMember: 1,
            nominationCount: 0
        )
        let bowl1 = CFBBowlSeason.makeWeekSummary(
            id: "2026-BOWL1",
            slot: .bowl1,
            rules: .default,
            memberCount: 8
        )
        #expect(CFBBowlSeason.compareWeekOrder(w15, bowl1))
        #expect(!CFBBowlSeason.compareWeekOrder(bowl1, w15))
    }

    @Test func settingsDefaultPickCountUsesSlateSize() {
        var rules = GroupRules.default
        rules.slateSize = 10
        rules.bowlSeason = .default
        #expect(rules.bowlSeason!.resolvedPickCount(rules: rules) == 10)
    }

    @Test func leaderboardShowsBowlScopeWhenConfigured() {
        #expect(LeaderboardScope.showsBowlScope(rules: .default))
        var rules = GroupRules.default
        rules.bowlSeason = CFBBowlSeason.Settings(
            mode: .modeA,
            isEnabled: false,
            pickCount: 12,
            countsTowardSeasonStandings: false,
            includesSecondWeek: false,
            suggestedRollingLock: true
        )
        #expect(!LeaderboardScope.showsBowlScope(rules: rules))
    }

    @Test func commissionerBowlBlockNotGatedByCalendarWeek() {
        #expect(CFBBowlSeason.Settings.resolved(from: .default).isConfigured)
        var rules = GroupRules.default
        rules.bowlSeason = CFBBowlSeason.Settings(
            mode: .modeA,
            isEnabled: false,
            pickCount: nil,
            countsTowardSeasonStandings: false,
            includesSecondWeek: false,
            suggestedRollingLock: true
        )
        #expect(!CFBBowlSeason.Settings.resolved(from: rules).isConfigured)
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

    @Test func modeBUsesSingleBowlWeekAndCatalogSlate() {
        var rules = GroupRules.default
        rules.bowlSeason = CFBBowlSeason.Settings(
            mode: .modeB,
            isEnabled: true,
            pickCount: nil,
            countsTowardSeasonStandings: false,
            includesSecondWeek: false,
            suggestedRollingLock: true
        )
        let slots = CFBBowlSeason.calendarSlots(seasonYear: 2026, settings: rules.bowlSeason!)
        #expect(slots.count == 1)
        #expect(slots[0].id == "2026-BOWL")
        let week = CFBBowlSeason.makeWeekSummary(
            id: "2026-BOWL",
            slot: .bowlAll,
            rules: rules,
            memberCount: 8
        )
        #expect(week.skipsSelection)
        #expect(week.bowlFullSlate == true)
        #expect(week.slateSource == CFBBowlSeason.bowlCatalogSlateSource)
    }

    @Test func modeBMakeWeekSummaryUsesRollingLock() {
        var rules = GroupRules.default
        rules.bowlSeason = CFBBowlSeason.Settings(
            mode: .modeB,
            isEnabled: true,
            pickCount: nil,
            countsTowardSeasonStandings: false,
            includesSecondWeek: false,
            suggestedRollingLock: true
        )
        let week = CFBBowlSeason.makeWeekSummary(
            id: "2026-BOWL",
            slot: .bowlAll,
            rules: rules,
            memberCount: 8
        )
        #expect(week.pickLockMode == .rolling)
        #expect(week.isRollingLock)
    }

    @Test func modeBCatalogIncludesCFPBracketKickoffs() {
        let opens = CFBBowlSeason.catalogOpens()
        let celebration = opens.addingTimeInterval(6 * 86_400)
        let cfpRound1 = opens.addingTimeInterval(10 * 86_400)
        let cfpQuarter = opens.addingTimeInterval(30 * 86_400)
        let championship = opens.addingTimeInterval(50 * 86_400)
        let bowl = WeekSummary(
            id: "2026-BOWL",
            seasonYear: 2026,
            weekNumber: 1,
            status: .picking,
            slateSize: 40,
            selectionMode: .commissioner,
            selectionsPerMember: 1,
            nominationCount: 0,
            slateSource: CFBBowlSeason.bowlCatalogSlateSource,
            bowlFullSlate: true,
            seasonType: 3,
            bowlSlot: "BOWL"
        )
        #expect(CFBBowlSeason.catalogEligible(kickoff: celebration, week: bowl))
        #expect(CFBBowlSeason.catalogEligible(kickoff: cfpRound1, week: bowl))
        #expect(CFBBowlSeason.belongsToBowlSlot(
            kickoff: cfpQuarter,
            slot: .bowlAll,
            fromEspnPostseasonWeek: CFBBowlSeason.Slot.bowl2.espnWeekNumber
        ))
        #expect(CFBBowlSeason.catalogEligible(kickoff: championship, week: bowl))
    }

    @Test func missingRulesStillDefaultToModeAPickSlate() {
        #expect(CFBBowlSeason.Settings.resolved(from: .default).mode == .modeA)
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