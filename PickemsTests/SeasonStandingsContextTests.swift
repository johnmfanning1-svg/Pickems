import Foundation
import Testing
@testable import Pickems

struct SeasonStandingsContextTests {
    @Test func seasonRankingDropsThisWeeksSlate() {
        let picks = [
            UserPick(id: "a", userId: "a", displayName: "Ann", picks: ["1": "home"], isLocked: true)
        ]
        let game = SlateGame(
            id: "1",
            espnEventId: "1",
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
            kickoff: Date(timeIntervalSince1970: 0),
            status: .final,
            homeScore: 28,
            awayScore: 17,
            winnerTeamId: "home"
        )
        let weekly = ScoringEngine.rankingPicksAndGames(weekly: true, picks: picks, games: [game])
        #expect(weekly.picks.count == 1)
        #expect(weekly.games.count == 1)
        let season = ScoringEngine.rankingPicksAndGames(weekly: false, picks: picks, games: [game])
        #expect(season.picks.isEmpty)
        #expect(season.games.isEmpty)
    }

    @Test func emptySeasonInputsLeaveATieToJoinDate() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        let entries = [
            StandingEntry(
                id: "late",
                displayName: "Late",
                avatarColorHex: "#111111",
                weeklyWins: 1,
                weeklyLosses: 0,
                seasonWins: 4,
                seasonLosses: 2,
                rank: 0,
                isTied: false,
                joinedAt: late
            ),
            StandingEntry(
                id: "early",
                displayName: "Early",
                avatarColorHex: "#222222",
                weeklyWins: 0,
                weeklyLosses: 1,
                seasonWins: 4,
                seasonLosses: 2,
                rank: 0,
                isTied: false,
                joinedAt: early
            ),
        ]
        let context = ScoringEngine.rankingPicksAndGames(
            weekly: false,
            picks: [
                UserPick(id: "late", userId: "late", displayName: "Late", picks: ["1": "home"], isLocked: true)
            ],
            games: []
        )
        let ranked = ScoringEngine.rankedStandings(
            entries: entries,
            weekly: false,
            tieBreaker: .headToHead,
            allPicks: context.picks,
            games: context.games
        )
        #expect(ranked.map(\.id) == ["early", "late"])
    }

    // Mirrors AppState.rankedStandings(weekly:): the same raw picks + slate go in
    // for both boards. Head-to-head this week favours "late"; the season tie
    // must still fall to join date.
    @Test func appStateBoardIgnoresThisWeekOnSeasonOnly() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        func entry(_ id: String, _ joined: Date, weeklyWins: Int) -> StandingEntry {
            StandingEntry(
                id: id, displayName: id.capitalized, avatarColorHex: "#111111",
                weeklyWins: weeklyWins, weeklyLosses: 1 - weeklyWins,
                seasonWins: 4, seasonLosses: 2,
                rank: 0, isTied: false, joinedAt: joined
            )
        }
        let entries = [entry("late", late, weeklyWins: 1), entry("early", early, weeklyWins: 1)]
        let game = SlateGame(
            id: "1", espnEventId: "1",
            homeTeamId: "home", homeTeamName: "Home", homeTeamAbbreviation: "HOM", homeTeamLogoURL: nil,
            awayTeamId: "away", awayTeamName: "Away", awayTeamAbbreviation: "AWY", awayTeamLogoURL: nil,
            spread: 7, spreadTeamId: "home",
            kickoff: Date(timeIntervalSince1970: 0), status: .final,
            homeScore: 28, awayScore: 17, winnerTeamId: "home"
        )
        let picks = [
            UserPick(id: "late", userId: "late", displayName: "Late", picks: ["1": "home"], isLocked: true),
            UserPick(id: "early", userId: "early", displayName: "Early", picks: ["1": "away"], isLocked: true),
        ]
        let season = ScoringEngine.boardStandings(
            entries: entries, weekly: false, tieBreaker: .headToHead,
            allPicks: picks, games: [game]
        )
        #expect(season.map(\.id) == ["early", "late"])
        let unfiltered = ScoringEngine.rankedStandings(
            entries: entries, weekly: false, tieBreaker: .headToHead,
            allPicks: picks, games: [game]
        )
        // Guard that the fixture really exercises the bug: without the filter,
        // this week's head-to-head would put "late" first.
        #expect(unfiltered.map(\.id) == ["late", "early"])
    }
}
