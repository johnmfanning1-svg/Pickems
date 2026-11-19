import Foundation
import Testing
@testable import Pickems

@MainActor
struct ReopenSelectionsViewModelTests {
    @Test func missingLeagueSurfacesErrorInsteadOfSilentReturn() {
        let vm = PicksViewModel()
        let appState = AppState()

        vm.reopenSelections(groupId: "missing", weekId: "2026-W12", appState: appState)

        #expect(appState.pickService.errorMessage == ReopenSelectionsPrompt.leagueUnavailableMessage)
        #expect(!vm.isReopeningSelections)
    }

    @Test func secondCallWhileInFlightIsIgnored() {
        let vm = PicksViewModel()
        let appState = AppState()
        vm.isReopeningSelections = true

        vm.reopenSelections(groupId: "any", weekId: "2026-W12", appState: appState)

        #expect(vm.isReopeningSelections)
        #expect(appState.pickService.errorMessage == nil)
    }

    @Test func missingUserSurfacesErrorBeforeAnyWrite() {
        let vm = PicksViewModel()
        let appState = AppState()
        appState.groupService.groups = [
            PickemGroup(
                id: "league-a",
                name: "League A",
                inviteCode: "ABC123",
                commissionerId: "u1",
                memberIds: ["u1"],
                rules: .default,
                createdAt: Date()
            )
        ]

        vm.reopenSelectionsWithDeadline(
            deadline: Date().addingTimeInterval(3600),
            groupId: "league-a",
            weekId: "2026-W12",
            appState: appState
        )

        #expect(appState.pickService.errorMessage == ReopenSelectionsPrompt.signInRequiredMessage)
        #expect(!vm.isReopeningSelections)
    }
}