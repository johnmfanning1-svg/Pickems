import Foundation
import Testing
@testable import Pickems

struct LeaguePickemsComparisonStatsTests {
    @Test func countsMatchingPicksOnVisibleGames() {
        let games = [game("g1"), game("g2"), game("g3")]
        let result = LeaguePickemsComparisonStats.samePickCount(
            games: games,
            youPicks: ["g1": "home", "g2": "away", "g3": "home"],
            themPicks: ["g1": "home", "g2": "home", "g3": "home"],
            hiddenGameIds: []
        )
        #expect(result.same == 2)
        #expect(result.visible == 3)
    }

    @Test func ignoresHiddenGamesAndEmptyPicks() {
        let games = [game("g1"), game("g2"), game("g3")]
        let result = LeaguePickemsComparisonStats.samePickCount(
            games: games,
            youPicks: ["g1": "home", "g2": "away", "g3": ""],
            themPicks: ["g1": "home", "g2": "away"],
            hiddenGameIds: ["g2"]
        )
        #expect(result.same == 1)
        #expect(result.visible == 2)
    }

    private func game(_ id: String) -> SlateGame {
        SlateGame(
            id: id,
            espnEventId: id,
            homeTeamId: "home",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "away",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            spread: 7,
            spreadTeamId: "home",
            kickoff: Date(),
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            winnerTeamId: nil
        )
    }
}
