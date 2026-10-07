import Foundation
import Testing
@testable import Pickems

struct LeaderboardScopeTests {
    private func week(status: WeekStatus) -> WeekSummary {
        WeekSummary(
            id: "2026-W6",
            seasonYear: 2026,
            weekNumber: 6,
            status: status,
            slateSize: 10,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0
        )
    }

    @Test func selectionSkippedAndUpcomingWeeksDefaultToSeason() {
        #expect(LeaderboardScope.defaultScope(for: week(status: .selection)) == .season)
    }

    @Test func pickingWeekDefaultsToThisWeek() {
        #expect(LeaderboardScope.defaultScope(for: week(status: .picking)) == .thisWeek)
    }

    @Test func lockedWeekThatIsNotScoredDefaultsToThisWeek() {
        #expect(LeaderboardScope.defaultScope(for: week(status: .locked)) == .thisWeek)
    }

    @Test func completedWeekDefaultsToSeason() {
        #expect(LeaderboardScope.defaultScope(for: week(status: .scored)) == .season)
    }

    @Test func missingWeekDefaultsToSeason() {
        let week: WeekSummary? = nil
        #expect(LeaderboardScope.defaultScope(for: week) == .season)
    }

    @Test func manualChoiceSticksOnTheSameLeagueWhenStatusChanges() {
        let choice = LeaderboardScope.ManualChoice(leagueId: "ppp", scope: .season)
        #expect(
            LeaderboardScope.resolvedScope(
                week: week(status: .picking),
                leagueId: "ppp",
                manual: choice
            ) == .season
        )
        let stayedOnThisWeek = LeaderboardScope.ManualChoice(leagueId: "ppp", scope: .thisWeek)
        #expect(
            LeaderboardScope.resolvedScope(
                week: week(status: .scored),
                leagueId: "ppp",
                manual: stayedOnThisWeek
            ) == .thisWeek
        )
    }

    @Test func manualChoiceDoesNotCarryToAnotherLeague() {
        let choice = LeaderboardScope.ManualChoice(leagueId: "ppp", scope: .season)
        #expect(
            LeaderboardScope.resolvedScope(
                week: week(status: .picking),
                leagueId: "og",
                manual: choice
            ) == .thisWeek
        )
    }

    @Test func leagueChipSwitchClearsManualChoice() {
        let choice = LeaderboardScope.ManualChoice(leagueId: "ppp", scope: .season)
        let cleared = LeaderboardScope.ManualChoice.afterLeagueChange(
            from: "ppp",
            to: "og",
            current: choice
        )
        #expect(cleared == LeaderboardScope.ManualChoice())
    }

    @Test func nilLeagueFlickerKeepsManualChoice() {
        let choice = LeaderboardScope.ManualChoice(leagueId: "ppp", scope: .season)
        let dropped = LeaderboardScope.ManualChoice.afterLeagueChange(
            from: "ppp",
            to: nil,
            current: choice
        )
        let restored = LeaderboardScope.ManualChoice.afterLeagueChange(
            from: nil,
            to: "ppp",
            current: choice
        )
        #expect(dropped == choice)
        #expect(restored == choice)
    }
}
