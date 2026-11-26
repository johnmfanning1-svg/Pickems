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

    @Test func staleWeekLoadDoesNotCommit() {
        #expect(!AvailableWeeksLoadCommit.shouldCommit(requestToken: 1, latestToken: 2))
    }

    @Test func freshestWeekLoadCommits() {
        #expect(AvailableWeeksLoadCommit.shouldCommit(requestToken: 2, latestToken: 2))
    }

    @Test func weekChipBarStaysLoadingUntilWeeksBelongToPin() {
        let loading = CommissionerPinnedLeague.WeekChipBarState.resolve(
            belongsToPin: false,
            availableWeeks: [week(deadline: 1)]
        )
        #expect(loading == .loading)
    }

    @Test func weekChipBarShowsEmptyWhenThePinHasNoWeeks() {
        let empty = CommissionerPinnedLeague.WeekChipBarState.resolve(
            belongsToPin: true,
            availableWeeks: []
        )
        #expect(empty == .empty)
    }

    @Test func weekChipBarShowsChipsWhenWeeksBelongToPin() {
        let sample = week(deadline: 42)
        let ready = CommissionerPinnedLeague.WeekChipBarState.resolve(
            belongsToPin: true,
            availableWeeks: [sample]
        )
        #expect(ready == .ready([sample]))
    }

    @Test func userChosenWeekSurvivesLateLoadSnapshot() {
        let live = week(deadline: 20)
        let browsed = week(id: "2026-W12", number: 12, deadline: 15)
        let resolved = CommissionerAdminWeekSelection.displayedWeek(
            userChosenWeekId: "2026-W12",
            observedWeek: live,
            commissionerWeeks: [browsed, live],
            weeksBelongToPin: true
        )
        #expect(resolved?.id == "2026-W12")
    }

    @Test func chipHighlightMatchesContentWeekId() {
        let live = week(id: "2026-W7", number: 7, deadline: 20)
        let browsed = week(id: "2026-W14", number: 14, deadline: 15)
        let fallbackBody = CommissionerAdminWeekSelection.displayedWeek(
            userChosenWeekId: "2026-W14",
            observedWeek: live,
            commissionerWeeks: [browsed, live],
            weeksBelongToPin: false
        )
        #expect(fallbackBody?.id == live.id)

        let pendingBody = CommissionerAdminWeekSelection.displayedWeek(
            userChosenWeekId: "2026-W14",
            observedWeek: live,
            commissionerWeeks: [browsed, live],
            weeksBelongToPin: true
        )
        #expect(pendingBody?.id == "2026-W14")
        #expect(pendingBody?.id != live.id)
    }

    @Test func adminRowsWaitUntilObservationMatchesDisplayedWeek() {
        #expect(!CommissionerAdminWeekSelection.adminWeekMatchesObservation(
            adminWeekId: "2026-W14",
            observedWeekId: "2026-W7"
        ))
        #expect(CommissionerAdminWeekSelection.adminWeekMatchesObservation(
            adminWeekId: "2026-W12",
            observedWeekId: "2026-W12"
        ))
    }

    @Test func userChosenWeekClearsWhenGroupObservationCatchesUp() {
        #expect(CommissionerAdminWeekSelection.shouldClearUserChosenWeek(
            observedWeekId: "2026-W12",
            userChosenWeekId: "2026-W12"
        ))
        #expect(!CommissionerAdminWeekSelection.shouldClearUserChosenWeek(
            observedWeekId: "2026-W7",
            userChosenWeekId: "2026-W12"
        ))
        #expect(!CommissionerAdminWeekSelection.shouldClearUserChosenWeek(
            observedWeekId: "2026-W12",
            userChosenWeekId: nil
        ))
    }

    @Test func writeRowsWaitForPickServiceObservedWeek() {
        #expect(CommissionerAdminWeekSelection.adminWeekReadyForWrites(
            adminWeekId: "2026-W12",
            groupObservedWeekId: "2026-W12",
            pickObservingGroupId: "g1",
            pickObservedWeekId: "2026-W12",
            settingsGroupId: "g1"
        ))
        #expect(!CommissionerAdminWeekSelection.adminWeekReadyForWrites(
            adminWeekId: "2026-W12",
            groupObservedWeekId: "2026-W12",
            pickObservingGroupId: "g1",
            pickObservedWeekId: "2026-W7",
            settingsGroupId: "g1"
        ))
    }

    @Test func pinnedListenerAcceptsSnapshotForObservedWeekWhenSeedMissed() {
        #expect(WeekObservationSnapshotPolicy.shouldApply(
            weekSelectionPinned: true,
            currentWeekId: "2026-W13",
            snapshotWeekId: "2026-W12",
            observedWeekId: "2026-W12"
        ))
        #expect(!WeekObservationSnapshotPolicy.shouldApply(
            weekSelectionPinned: true,
            currentWeekId: "2026-W13",
            snapshotWeekId: "2026-W7",
            observedWeekId: "2026-W12"
        ))
    }

    @Test func weekListScrollStaysPutAfterUserTap() {
        #expect(!WeekChipBarScrollSync.shouldScrollOnWeekListChange(userHasChosenWeek: true))
        #expect(WeekChipBarScrollSync.shouldScrollOnWeekListChange(userHasChosenWeek: false))
    }

    private func week(
        id: String = "2026-W7",
        number: Int = 7,
        deadline: TimeInterval
    ) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: 2026,
            weekNumber: number,
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
