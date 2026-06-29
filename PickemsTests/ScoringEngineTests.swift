import Foundation
import Testing
@testable import Pickems

struct ScoringEngineTests {
    @Test func pickCorrectWhenFavoriteCovers() {
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
            kickoff: Date(),
            status: .final,
            homeScore: 28,
            awayScore: 17,
            winnerTeamId: "home"
        )

        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: game) == true)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "away", game: game) == false)
    }

    @Test func pickPushReturnsNil() {
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
            kickoff: Date(),
            status: .final,
            homeScore: 24,
            awayScore: 17,
            winnerTeamId: "home"
        )

        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: game) == nil)
    }

    @Test func slateCompletionRules() {
        #expect(ScoringEngine.isSlateComplete(nominationCount: 12, slateSize: 12))
        #expect(!ScoringEngine.isSlateComplete(nominationCount: 11, slateSize: 12))
        #expect(ScoringEngine.canSubmitNomination(userNominationCount: 2, selectionsPerMember: 3, totalNominations: 10, slateSize: 12))
        #expect(!ScoringEngine.canSubmitNomination(userNominationCount: 3, selectionsPerMember: 3, totalNominations: 10, slateSize: 12))
    }

    @Test func rankedStandingsAssignsRanks() {
        let entries = [
            StandingEntry(id: "a", displayName: "A", avatarColorHex: "#DC2626", weeklyWins: 5, weeklyLosses: 2, seasonWins: 10, seasonLosses: 5, rank: 0, isTied: false),
            StandingEntry(id: "b", displayName: "B", avatarColorHex: "#3366CC", weeklyWins: 3, weeklyLosses: 4, seasonWins: 8, seasonLosses: 7, rank: 0, isTied: false),
        ]
        let ranked = ScoringEngine.rankedStandings(entries: entries, weekly: true, tieBreaker: .commissionerOverride)
        #expect(ranked[0].rank == 1)
        #expect(ranked[1].rank == 2)
    }

    @Test func rankedStandingsBreaksTiesByBattingAverage() {
        let entries = [
            StandingEntry(id: "a", displayName: "A", avatarColorHex: "#DC2626", weeklyWins: 4, weeklyLosses: 4, seasonWins: 10, seasonLosses: 5, rank: 0, isTied: false),
            StandingEntry(id: "b", displayName: "B", avatarColorHex: "#3366CC", weeklyWins: 4, weeklyLosses: 2, seasonWins: 8, seasonLosses: 7, rank: 0, isTied: false),
        ]
        let ranked = ScoringEngine.rankedStandings(entries: entries, weekly: true, tieBreaker: .commissionerOverride)
        #expect(ranked[0].id == "b")
        #expect(ranked[1].id == "a")
    }

    @Test func commissionerOverrideMarksEqualRecordsAsTied() {
        let entries = [
            StandingEntry(id: "a", displayName: "A", avatarColorHex: "#DC2626", weeklyWins: 4, weeklyLosses: 2, seasonWins: 10, seasonLosses: 5, rank: 0, isTied: false),
            StandingEntry(id: "b", displayName: "B", avatarColorHex: "#3366CC", weeklyWins: 4, weeklyLosses: 2, seasonWins: 8, seasonLosses: 7, rank: 0, isTied: false),
        ]
        let ranked = ScoringEngine.rankedStandings(entries: entries, weekly: true, tieBreaker: .commissionerOverride)
        #expect(ranked[0].isTied == false)
        #expect(ranked[1].isTied)
        #expect(ranked[1].rank == 1)
    }

    @Test func underdogCoverIsCorrect() {
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
            spread: 3.5,
            spreadTeamId: "home",
            kickoff: Date(),
            status: .final,
            homeScore: 21,
            awayScore: 24,
            winnerTeamId: "away"
        )

        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "away", game: game) == true)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: game) == false)
    }

    @Test func threeWayHeadToHeadBreaksTieGroup() {
        let game = SlateGame(
            id: "g1",
            espnEventId: "g1",
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
            status: .final,
            homeScore: 28,
            awayScore: 17,
            winnerTeamId: "home"
        )

        let entries = [
            StandingEntry(id: "a", displayName: "Alice", avatarColorHex: "#DC2626", weeklyWins: 8, weeklyLosses: 4, seasonWins: 8, seasonLosses: 4, rank: 0, isTied: false),
            StandingEntry(id: "b", displayName: "Bob", avatarColorHex: "#3366CC", weeklyWins: 8, weeklyLosses: 4, seasonWins: 8, seasonLosses: 4, rank: 0, isTied: false),
            StandingEntry(id: "c", displayName: "Carol", avatarColorHex: "#22AA44", weeklyWins: 8, weeklyLosses: 4, seasonWins: 8, seasonLosses: 4, rank: 0, isTied: false),
        ]

        let picks = [
            UserPick(id: "a", userId: "a", displayName: "Alice", picks: ["g1": "home"], submittedAt: Date(), isLocked: true),
            UserPick(id: "b", userId: "b", displayName: "Bob", picks: ["g1": "away"], submittedAt: Date(), isLocked: true),
            UserPick(id: "c", userId: "c", displayName: "Carol", picks: ["g1": "away"], submittedAt: Date(), isLocked: true),
        ]

        let ranked = ScoringEngine.rankedStandings(
            entries: entries,
            weekly: true,
            tieBreaker: .headToHead,
            allPicks: picks,
            games: [game]
        )

        #expect(ranked[0].id == "a")
        #expect(ranked[0].rank == 1)
        #expect(!ranked[0].isTied)
    }
}

struct GroupRulesTests {
    @Test func defaultRulesMatchSpec() {
        let rules = GroupRules.default
        #expect(rules.selectionMode == .member)
        #expect(rules.selectionsPerMember == 3)
        #expect(rules.slateSize == 12)
    }
}
