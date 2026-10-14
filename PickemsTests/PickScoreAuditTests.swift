import Foundation
import Testing
@testable import Pickems

/// Gaps the October 2026 audit wanted locked in: half-points, pick'em, the line
/// that is actually graded, confidence pushes, and head-to-head on a season tie.
struct PickScoreAuditTests {
    @Test func halfPointLineNeverPushes() {
        let short = lineGame(spread: 3.5, spreadTeamId: "home", homeScore: 24, awayScore: 21)
        let cover = lineGame(spread: 3.5, spreadTeamId: "home", homeScore: 28, awayScore: 24)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: short) == false)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "away", game: short) == true)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: cover) == true)
        #expect(ScoringEngine.pickBoardStatus(pickedTeamId: "home", game: short) == .lost)
        #expect(ScoringEngine.scorePicks(picks: ["1": "home"], games: [short]).pushes == 0)

        let awayShort = lineGame(spread: 3.5, spreadTeamId: "away", homeScore: 21, awayScore: 24)
        let awayCover = lineGame(spread: 3.5, spreadTeamId: "away", homeScore: 21, awayScore: 28)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: awayShort) == true)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "away", game: awayCover) == true)
    }

    @Test func negativeSpreadMatchesPositive() {
        let positive = lineGame(spread: 7, spreadTeamId: "home", homeScore: 24, awayScore: 17)
        let negative = lineGame(spread: -7, spreadTeamId: "home", homeScore: 24, awayScore: 17)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: positive) == nil)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: negative) == nil)
        let cover = lineGame(spread: -7, spreadTeamId: "home", homeScore: 28, awayScore: 17)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: cover) == true)
    }

    @Test func pickEmPushesOnlyOnATie() {
        let tie = lineGame(spread: 0, spreadTeamId: "home", homeScore: 17, awayScore: 17)
        let homeWin = lineGame(spread: 0, spreadTeamId: "home", homeScore: 21, awayScore: 17)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: tie) == nil)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: homeWin) == true)
        #expect(ScoringEngine.scorePicks(picks: ["1": "away"], games: [homeWin]).losses == 1)
    }

    @Test func straightUpIgnoresAHalfPointLine() {
        let atsDog = lineGame(spread: 3.5, spreadTeamId: "home", homeScore: 24, awayScore: 21)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: atsDog) == false)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: atsDog, pickMode: .straightUp) == true)
        let tie = lineGame(spread: 3.5, spreadTeamId: "home", homeScore: 21, awayScore: 21)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: tie, pickMode: .straightUp) == nil)
    }

    @Test func confidenceDoublesALossAndDoesNotDoubleAPush() {
        let loss = lineGame(spread: 7, spreadTeamId: "home", homeScore: 10, awayScore: 24)
        let doubled = ScoringEngine.scorePicks(picks: ["1": "home"], games: [loss], confidenceGameId: "1")
        #expect(doubled.wins == 0)
        #expect(doubled.losses == 2)
        #expect(doubled.pushes == 0)
        let push = lineGame(spread: 7, spreadTeamId: "home", homeScore: 24, awayScore: 17)
        let once = ScoringEngine.scorePicks(picks: ["1": "home"], games: [push], confidenceGameId: "1")
        #expect(once.wins == 0)
        #expect(once.losses == 0)
        #expect(once.pushes == 1)
    }

    @Test func blankPickIsALoss() {
        let push = lineGame(spread: 7, spreadTeamId: "home", homeScore: 24, awayScore: 17)
        let blank = ScoringEngine.scorePicks(picks: ["1": "   "], games: [push])
        #expect(blank.losses == 1)
        #expect(blank.pushes == 0)
    }

    /// October audit: a line edit after the pick (7 → 6.5) regraded a push as a
    /// win. Since #91 the line freezes at kickoff (`lockedSpread`) and grading
    /// uses it, so a later edit to `spread` does not regrade.
    @Test func lineEditAfterLockDoesNotRegrade() {
        var moved = lineGame(spread: 7, spreadTeamId: "home", homeScore: 24, awayScore: 17)
        moved.lockedSpread = 7
        moved.lockedSpreadTeamId = "home"
        moved.spread = 6.5
        let graded = ScoringEngine.scorePicks(picks: ["1": "home"], games: [moved])
        #expect(graded.pushes == 1)
        #expect(graded.wins == 0)
    }

    @Test func headToHeadIgnoresSameSidePicksAndPushes() {
        let decided = lineGame(spread: 7, spreadTeamId: "home", homeScore: 28, awayScore: 17)
        var push = decided
        push.id = "2"
        push.homeScore = 24
        push.awayScore = 17
        let picks = [
            UserPick(id: "a", userId: "a", displayName: "Ann", picks: ["1": "home", "2": "home"], isLocked: true),
            UserPick(id: "b", userId: "b", displayName: "Bea", picks: ["1": "away", "2": "away"], isLocked: true),
        ]
        let points = ScoringEngine.headToHeadPoints(
            userA: "a",
            userB: "b",
            picksByUser: Dictionary(uniqueKeysWithValues: picks.map { ($0.userId, $0.picks) }),
            games: [decided, push]
        )
        #expect(points.a == 1)
        #expect(points.b == 0)
    }

    /// Season ties fall to join date; this week's games must not decide them
    /// (see #86). Head-to-head from this week's slate applies to the weekly board.
    @Test func seasonTieIgnoresThisWeekWeeklyTieUsesHeadToHead() {
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
        let byJoin = ScoringEngine.rankedStandings(
            entries: entries,
            weekly: false,
            tieBreaker: .headToHead
        )
        #expect(byJoin.map(\.id) == ["early", "late"])

        let game = lineGame(spread: 7, spreadTeamId: "home", homeScore: 28, awayScore: 17)
        let picks = [
            UserPick(id: "late", userId: "late", displayName: "Late", picks: ["1": "home"], isLocked: true),
            UserPick(id: "early", userId: "early", displayName: "Early", picks: ["1": "away"], isLocked: true),
        ]
        var weeklyTie = entries
        for i in weeklyTie.indices {
            weeklyTie[i].weeklyWins = 1
            weeklyTie[i].weeklyLosses = 0
        }
        let weeklyBoard = ScoringEngine.rankedStandings(
            entries: weeklyTie,
            weekly: true,
            tieBreaker: .headToHead,
            allPicks: picks,
            games: [game]
        )
        #expect(weeklyBoard.map(\.id) == ["late", "early"])
    }

    private func lineGame(
        spread: Double,
        spreadTeamId: String,
        homeScore: Int,
        awayScore: Int
    ) -> SlateGame {
        SlateGame(
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
            spread: spread,
            spreadTeamId: spreadTeamId,
            kickoff: Date(timeIntervalSince1970: 0),
            status: .final,
            homeScore: homeScore,
            awayScore: awayScore,
            winnerTeamId: nil
        )
    }
}
