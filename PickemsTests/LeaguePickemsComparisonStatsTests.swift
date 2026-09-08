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

    @Test func orderedWeeksAreOldestOnTheLeft() {
        let weeks = [
            week(id: "2026-W2", year: 2026, number: 2),
            week(id: "2025-W14", year: 2025, number: 14),
            week(id: "2026-W0", year: 2026, number: 0),
        ]
        let ordered = LeaguePickemsComparisonCopy.orderedWeeks(weeks)
        #expect(ordered.map(\.id) == ["2025-W14", "2026-W0", "2026-W2"])
    }

    @Test func pendingCopyMentionsSelectionsThenRollingLock() {
        let copy = LeaguePickemsComparisonCopy.pendingBoard(isRolling: true, isSelection: true)
        #expect(copy.title == "This week's Pickems aren't public yet")
        #expect(copy.message.contains("Selections close"))
        #expect(copy.message.contains("kickoff"))
    }

    @Test func pendingCopyMentionsSelectionsThenFullLock() {
        let copy = LeaguePickemsComparisonCopy.pendingBoard(isRolling: false, isSelection: true)
        #expect(copy.message.contains("Selections close"))
        #expect(copy.message.contains("Pickems lock"))
        #expect(!copy.message.contains("kickoff"))
    }

    @Test func gamesAheadIsWinDifference() {
        #expect(LeaguePickemsComparisonStats.gamesAhead(youWins: 5, themWins: 3) == 2)
        #expect(LeaguePickemsComparisonStats.gamesAhead(youWins: 4, themWins: 4) == 0)
        #expect(LeaguePickemsComparisonStats.gamesAhead(youWins: 3, themWins: 4) == -1)
        #expect(LeaguePickemsComparisonStats.gamesAhead(youWins: 5, themWins: 4) == 1)
    }

    @Test func gapPhraseSwitchesAheadBackAndEven() {
        #expect(LeaguePickemsComparisonStats.gapPhrase(gamesAhead: 1) == "1 game ahead")
        #expect(LeaguePickemsComparisonStats.gapPhrase(gamesAhead: -2) == "2 games back")
        #expect(LeaguePickemsComparisonStats.gapPhrase(gamesAhead: 0) == "Even")
    }

    private func week(id: String, year: Int, number: Int) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: year,
            weekNumber: number,
            status: .scored,
            slateSize: 4,
            selectionMode: .member,
            selectionsPerMember: 1,
            nominationCount: 0
        )
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
