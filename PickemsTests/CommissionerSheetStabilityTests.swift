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
        let resolved = SlateSpreadPresentation.game(captured: captured, liveGames: [other])
        #expect(resolved.id == "thu")
        #expect(resolved.spread == 3)
    }

    @Test func spreadEditorUsesLiveGameWithTheSameId() {
        let captured = game(id: "thu", spread: 3)
        let live = game(id: "thu", spread: 6.5)
        let resolved = SlateSpreadPresentation.game(captured: captured, liveGames: [live])
        #expect(resolved.id == "thu")
        #expect(resolved.spread == 6.5)
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
