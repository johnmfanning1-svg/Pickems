import Foundation
import Testing
@testable import Pickems

struct LeaguePickModeSwitchTests {
    private func week(
        id: String = "2026-W5",
        weekNumber: Int = 5,
        status: WeekStatus,
        nominationCount: Int = 0,
        slateSource: String? = nil,
        pickMode: PickMode? = nil
    ) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: 2026,
            weekNumber: weekNumber,
            status: status,
            slateSize: 6,
            selectionMode: .member,
            selectionsPerMember: 2,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: nominationCount,
            slateSource: slateSource,
            pickMode: pickMode
        )
    }

    // MARK: Phase

    @Test func noWeekAppliesEverywhere() {
        let phase = LeaguePickModeSwitch.phase(week: nil, selectionsMade: 0)
        #expect(phase == .noCurrentWeek)
        #expect(LeaguePickModeSwitch.decision(for: phase) == .applyNow(weekId: nil))
    }

    @Test func selectionsNotStartedAppliesToThisWeek() {
        let phase = LeaguePickModeSwitch.phase(week: week(status: .selection), selectionsMade: 0)
        #expect(phase == .selectionsNotStarted(weekId: "2026-W5"))
        #expect(LeaguePickModeSwitch.decision(for: phase) == .applyNow(weekId: "2026-W5"))
    }

    @Test func selectionsStartedFromLoadedNominationsAsks() {
        let phase = LeaguePickModeSwitch.phase(week: week(status: .selection), selectionsMade: 1)
        #expect(phase == .selectionsStarted(weekId: "2026-W5"))
        #expect(LeaguePickModeSwitch.decision(for: phase) == .ask(weekId: "2026-W5"))
    }

    @Test func selectionsStartedFromWeekCountAsks() {
        let phase = LeaguePickModeSwitch.phase(week: week(status: .selection, nominationCount: 3), selectionsMade: 0)
        #expect(LeaguePickModeSwitch.decision(for: phase) == .ask(weekId: "2026-W5"))
    }

    @Test func fixedSlateWeekNeverAsks() {
        let weekZero = week(
            id: "2026-W0",
            weekNumber: 0,
            status: .selection,
            nominationCount: 4,
            slateSource: CFBWeekCalendar.weekZeroSlateSource
        )
        let phase = LeaguePickModeSwitch.phase(week: weekZero, selectionsMade: 4)
        #expect(phase == .selectionsNotStarted(weekId: "2026-W0"))
    }

    @Test func pickemsOpenOrLockedIsNextWeekOnly() {
        for status in [WeekStatus.picking, .locked] {
            let phase = LeaguePickModeSwitch.phase(week: week(status: status), selectionsMade: 6)
            #expect(phase == .pickemsStarted(weekId: "2026-W5"))
            #expect(LeaguePickModeSwitch.decision(for: phase) == .nextWeekOnly(weekId: "2026-W5"))
        }
    }

    @Test func scoredWeekIsNextWeekOnly() {
        let phase = LeaguePickModeSwitch.phase(week: week(status: .scored), selectionsMade: 0)
        #expect(phase == .weekScored(weekId: "2026-W5"))
        #expect(LeaguePickModeSwitch.decision(for: phase) == .nextWeekOnly(weekId: "2026-W5"))
    }

    // MARK: Copy

    @Test func askCopyNamesBothChoices() {
        let message = LeaguePickModeSwitch.askMessage(newMode: .straightUp, currentMode: .ats)
        #expect(message.contains(LeaguePickModeSwitch.applyNowTitle))
        #expect(message.contains(LeaguePickModeSwitch.nextWeekTitle))
        #expect(message.contains("Straight Up"))
        #expect(LeaguePickModeSwitch.applyNowTitle == "Apply to this week and going forward")
        #expect(LeaguePickModeSwitch.nextWeekTitle == "Start next week")
    }

    @Test func nextWeekOnlyCopyDoesNotOfferThisWeek() {
        let open = LeaguePickModeSwitch.nextWeekOnlyMessage(newMode: .ats, currentMode: .straightUp, weekScored: false)
        let scored = LeaguePickModeSwitch.nextWeekOnlyMessage(newMode: .ats, currentMode: .straightUp, weekScored: true)
        #expect(open.hasPrefix("Pickems are already open"))
        #expect(scored.hasPrefix("This week is already scored"))
        #expect(open.contains("starts next week"))
        #expect(!open.contains(LeaguePickModeSwitch.applyNowTitle))
    }

    @Test func successCopyMatchesOutcome() {
        #expect(LeaguePickModeSwitch.successMessage(newMode: .straightUp, appliedToCurrentWeek: true, hadCurrentWeek: true, currentMode: .ats)
            == "League type is Straight Up, starting this week.")
        #expect(LeaguePickModeSwitch.successMessage(newMode: .straightUp, appliedToCurrentWeek: false, hadCurrentWeek: true, currentMode: .ats)
            .contains("This week stays Against the Spread"))
        #expect(LeaguePickModeSwitch.successMessage(newMode: .ats, appliedToCurrentWeek: true, hadCurrentWeek: false, currentMode: .straightUp)
            .contains("every week going forward"))
    }

    // MARK: Resolution after a switch

    @Test func pinnedWeekKeepsItsModeAfterLeagueSwitch() {
        let pinned = week(status: .picking, pickMode: .ats)
        #expect(pinned.resolvedPickMode(leagueMode: .straightUp) == .ats)
        let inheriting = week(id: "2026-W6", weekNumber: 6, status: .selection)
        #expect(inheriting.resolvedPickMode(leagueMode: .straightUp) == .straightUp)
    }
}
