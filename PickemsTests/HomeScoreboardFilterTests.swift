import Foundation
import Testing
@testable import Pickems

struct HomeScoreboardFilterTests {
    @Test func power4IdsMatchCatalogHead() {
        #expect(ESPNConferenceCatalog.power4Ids == Set(["8", "5", "4", "1"]))
        #expect(ESPNConferenceCatalog.isPower4("8"))
        #expect(ESPNConferenceCatalog.isPower4("5"))
        #expect(!ESPNConferenceCatalog.isPower4("151"))
        #expect(!ESPNConferenceCatalog.isPower4(nil))
    }

    @Test func cardMatchesPower4WhenEitherSideIsPower4() {
        let sec = makeCard(homeConferenceId: "8", awayConferenceId: "151")
        let g5 = makeCard(homeConferenceId: "151", awayConferenceId: "17")
        #expect(sec.matches(.power4))
        #expect(!g5.matches(.power4))
    }

    @Test func cardMatchesTop25MyPicksAndGroupSlate() {
        var card = makeCard(isTop25: true, isSlateGame: true, pickAbbr: "ALA")
        #expect(card.matches(.top25))
        #expect(card.matches(.myPicks))
        #expect(card.matches(.groupSlate))
        #expect(card.matches(.all))

        card = makeCard(isTop25: false, isSlateGame: false, pickAbbr: nil)
        #expect(!card.matches(.top25))
        #expect(!card.matches(.myPicks))
        #expect(!card.matches(.groupSlate))
        #expect(card.matches(.all))
    }

    @Test func cardMatchesConferenceFilter() {
        let card = makeCard(homeConferenceId: "1", awayConferenceId: "9")
        #expect(card.matches(.conference(id: "1")))
        #expect(card.matches(.conference(id: "9")))
        #expect(!card.matches(.conference(id: "8")))
    }

    private func makeCard(
        homeConferenceId: String? = "8",
        awayConferenceId: String? = "5",
        isTop25: Bool = false,
        isSlateGame: Bool = false,
        pickAbbr: String? = nil
    ) -> ESPNLiveGameCard {
        ESPNLiveGameCard(
            id: "evt-1",
            espnEventId: "evt-1",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayScore: nil,
            homeScore: nil,
            spreadLabel: nil,
            status: .scheduled,
            statusDetail: "Upcoming",
            kickoff: Date(),
            isSlateGame: isSlateGame,
            isTop25: isTop25,
            homeConferenceId: homeConferenceId,
            awayConferenceId: awayConferenceId,
            userPickTeamAbbreviation: pickAbbr,
            pickResult: nil
        )
    }
}

@MainActor
struct PicksDraftSyncTests {
    @Test func syncDraftFromServerClearsEmptyPicks() {
        let vm = PicksViewModel()
        vm.draftPicks = ["game-1": "team-a", "game-2": "team-b"]
        vm.confidenceGameId = "game-1"

        vm.syncDraftFromServer([:], confidenceGameId: nil)

        #expect(vm.draftPicks.isEmpty)
        #expect(vm.confidenceGameId == nil)
    }

    @Test func syncDraftFromServerClearsNilPicks() {
        let vm = PicksViewModel()
        vm.draftPicks = ["game-1": "team-a"]
        vm.confidenceGameId = "game-1"

        vm.syncDraftFromServer(nil, confidenceGameId: nil)

        #expect(vm.draftPicks.isEmpty)
        #expect(vm.confidenceGameId == nil)
    }

    @Test func syncDraftFromServerReplacesWithServerMap() {
        let vm = PicksViewModel()
        vm.draftPicks = ["stale": "old"]

        vm.syncDraftFromServer(["game-1": "team-a"], confidenceGameId: "game-1")

        #expect(vm.draftPicks == ["game-1": "team-a"])
        #expect(vm.confidenceGameId == "game-1")
    }

    @Test func syncDraftFromServerDropsBlankTeamIds() {
        let vm = PicksViewModel()
        vm.draftPicks = ["game-1": "team-a"]
        vm.confidenceGameId = "game-1"

        vm.syncDraftFromServer(["game-1": "", "game-2": "team-b"], confidenceGameId: "game-1")

        #expect(vm.draftPicks == ["game-2": "team-b"])
        #expect(vm.confidenceGameId == nil)
    }

    @Test func sanitizedPicksDropsBlankEntries() {
        let cleaned = PickService.sanitizedPicks([
            "game-1": "team-a",
            "game-2": "",
            "": "team-b",
            "  ": "  ",
        ])
        #expect(cleaned == ["game-1": "team-a"])
    }
}
