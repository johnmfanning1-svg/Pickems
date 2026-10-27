import Foundation
import Testing
@testable import Pickems

struct CommissionerSheetStabilityTests {
    @Test func pinBeatsADifferentLiveLeague() {
        #expect(CommissionerSheetStability.presenterGroupId(liveGroupId: "live", retainedGroupId: "pinned") == "pinned")
    }

    @Test func nilLiveLeagueKeepsThePin() {
        #expect(CommissionerSheetStability.presenterGroupId(liveGroupId: nil, retainedGroupId: "pinned") == "pinned")
    }

    @Test func nilPinUsesTheLiveLeague() {
        #expect(CommissionerSheetStability.presenterGroupId(liveGroupId: "live", retainedGroupId: nil) == "live")
        #expect(CommissionerSheetStability.presenterGroupId(liveGroupId: nil, retainedGroupId: nil) == nil)
    }

    @Test func sameLeagueKeepsTheSheetRoute() {
        let route = CommissionerSheetStability.routeAfterGroupRefresh(
            route: "selectionDeadline",
            previousGroupId: "g1",
            groupId: "g1"
        )
        #expect(route == "selectionDeadline")
    }

    @Test func differentLeagueDropsTheSheetRoute() {
        let route = CommissionerSheetStability.routeAfterGroupRefresh(
            route: "members",
            previousGroupId: "g1",
            groupId: "g2"
        )
        #expect(route == nil)
    }

    @Test func missingLeagueDropsTheSheetRoute() {
        let route = CommissionerSheetStability.routeAfterGroupRefresh(
            route: "slate",
            previousGroupId: "g1",
            groupId: nil
        )
        #expect(route == nil)
    }

    @Test func firstObservationKeepsARouteThatWasJustSet() {
        let route = CommissionerSheetStability.routeAfterGroupRefresh(
            route: "pickDeadline",
            previousGroupId: nil,
            groupId: "g1"
        )
        #expect(route == "pickDeadline")
    }

    @Test func spreadEditorKeepsCapturedGameWhenSlateRefreshDropsIt() {
        let captured = game(id: "thu", spread: 3)
        let other = game(id: "sun", spread: 7)
        let resolved = SlateSpreadPresentation.game(captured: captured, liveGames: [other], liveBelongsToLeague: true)
        #expect(resolved.id == "thu")
        #expect(resolved.spread == 3)
    }

    @Test func settingsDismissWhenTheSelectedLeagueChanges() {
        #expect(CommissionerPinnedLeague.shouldDismiss(
            settingsOpen: true, pinnedGroupId: "pinned", liveGroupId: "other"
        ))
        #expect(!CommissionerPinnedLeague.shouldDismiss(
            settingsOpen: true, pinnedGroupId: "pinned", liveGroupId: nil
        ))
        #expect(!CommissionerPinnedLeague.shouldDismiss(
            settingsOpen: true, pinnedGroupId: "pinned", liveGroupId: "pinned"
        ))
        #expect(!CommissionerPinnedLeague.shouldDismiss(
            settingsOpen: false, pinnedGroupId: "pinned", liveGroupId: "other"
        ))
    }

    @Test func sharedWeekIdDoesNotReadAnotherLeaguesCurrentWeek() {
        let captured = week(deadline: 10)
        let other = week(deadline: 99)
        let resolved = CommissionerPinnedLeague.week(
            pinnedGroupId: "pinned",
            weekId: "2026-W7",
            captured: captured,
            current: other,
            currentGroupId: "other",
            available: [other],
            availableBelongsToPin: false
        )
        #expect(resolved?.pickDeadline == captured.pickDeadline)
    }

    @Test func liveWeekWinsWhenTheObserverIsStillThePin() {
        let captured = week(deadline: 10)
        let live = week(deadline: 20)
        let resolved = CommissionerPinnedLeague.week(
            pinnedGroupId: "pinned",
            weekId: "2026-W7",
            captured: captured,
            current: live,
            currentGroupId: "pinned",
            available: [captured],
            availableBelongsToPin: true
        )
        #expect(resolved?.pickDeadline == live.pickDeadline)
    }

    @Test func availableWeeksAreSkippedUntilTheyBelongToThePin() {
        let foreign = CommissionerPinnedLeague.week(
            pinnedGroupId: "pinned",
            weekId: "2026-W7",
            captured: nil,
            current: nil,
            currentGroupId: "other",
            available: [week(deadline: 99)],
            availableBelongsToPin: false
        )
        let own = CommissionerPinnedLeague.week(
            pinnedGroupId: "pinned",
            weekId: "2026-W7",
            captured: nil,
            current: nil,
            currentGroupId: nil,
            available: [week(deadline: 30)],
            availableBelongsToPin: true
        )
        #expect(foreign == nil)
        #expect(own?.pickDeadline == Date(timeIntervalSince1970: 30))
    }

    @Test func pinnedGroupIgnoresADifferentSelection() {
        let pinned = CommissionerSheetStability.placeholderGroup(id: "pinned")
        let other = CommissionerSheetStability.placeholderGroup(id: "other")
        let resolved = CommissionerPinnedLeague.group(
            id: "pinned", selected: other, listed: [pinned], fallback: nil
        )
        let missing = CommissionerPinnedLeague.group(
            id: "pinned", selected: other, listed: [other], fallback: nil
        )
        #expect(resolved?.id == "pinned")
        #expect(missing == nil)
    }

    @Test func slateStaysWithThePinWhenTheObserverLeaves() {
        let captured = [game(id: "thu", spread: 3)]
        let live = [game(id: "thu", spread: 9)]
        let stayed = CommissionerPinnedLeague.slate(
            pinnedGroupId: "pinned", observingGroupId: "other", live: live, captured: captured
        )
        let following = CommissionerPinnedLeague.slate(
            pinnedGroupId: "pinned", observingGroupId: "pinned", live: live, captured: captured
        )
        #expect(stayed.first?.spread == 3)
        #expect(following.first?.spread == 9)
    }

    @Test func spreadEditorIgnoresAnotherLeaguesLiveGame() {
        let captured = game(id: "thu", spread: 3)
        let live = game(id: "thu", spread: 9)
        let resolved = SlateSpreadPresentation.game(
            captured: captured, liveGames: [live], liveBelongsToLeague: false
        )
        #expect(resolved.spread == 3)
    }

    @Test func uneditedSpreadDraftFollowsTheServerLine() {
        let draft = SpreadDraftRefresh.Draft(spread: 3, favoriteIsHome: true, didEdit: false)
        let next = SpreadDraftRefresh.afterServerLine(draft, spread: -7.5, favoriteIsHome: false)
        #expect(next.spread == 7.5)
        #expect(next.favoriteIsHome == false)
        #expect(!SpreadDraftRefresh.showsLineChangedWarning(
            draft: next, serverSpread: -7.5, serverFavoriteIsHome: false
        ))
    }

    @Test func editedSpreadDraftKeepsTheCommissionerLineAndWarns() {
        let draft = SpreadDraftRefresh.Draft(spread: 3, favoriteIsHome: true, didEdit: true)
        let next = SpreadDraftRefresh.afterServerLine(draft, spread: 7, favoriteIsHome: false)
        #expect(next == draft)
        #expect(SpreadDraftRefresh.showsLineChangedWarning(
            draft: next, serverSpread: 7, serverFavoriteIsHome: false
        ))
        #expect(!SpreadDraftRefresh.showsLineChangedWarning(
            draft: next, serverSpread: 3, serverFavoriteIsHome: true
        ))
    }

    @Test func spreadEditorUsesLiveGameWithTheSameId() {
        let captured = game(id: "thu", spread: 3)
        let live = game(id: "thu", spread: 6.5)
        let resolved = SlateSpreadPresentation.game(captured: captured, liveGames: [live], liveBelongsToLeague: true)
        #expect(resolved.id == "thu")
        #expect(resolved.spread == 6.5)
    }

    private func week(deadline: TimeInterval) -> WeekSummary {
        WeekSummary(
            id: "2026-W7",
            seasonYear: 2026,
            weekNumber: 7,
            status: .picking,
            slateSize: 2,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: Date(timeIntervalSince1970: deadline),
            nominationCount: 0
        )
    }

    private func game(id: String, spread: Double) -> SlateGame {
        SlateGame(
            id: id,
            espnEventId: id,
            homeTeamId: "h",
            homeTeamName: "Home",
            homeTeamAbbreviation: "H",
            homeTeamLogoURL: nil,
            awayTeamId: "a",
            awayTeamName: "Away",
            awayTeamAbbreviation: "A",
            awayTeamLogoURL: nil,
            spread: spread,
            spreadTeamId: "h",
            kickoff: Date(timeIntervalSince1970: 1_800_000_000),
            status: .scheduled
        )
    }
}
