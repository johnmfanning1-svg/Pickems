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
        #expect(ScoringEngine.canSubmitNomination(
            userNominationCount: 2,
            selectionsPerMember: 3,
            uniqueNominationCount: 10,
            slateSize: 12,
            selectionDeadline: nil
        ))
        #expect(!ScoringEngine.canSubmitNomination(
            userNominationCount: 3,
            selectionsPerMember: 3,
            uniqueNominationCount: 10,
            slateSize: 12,
            selectionDeadline: nil
        ))
        let past = Date().addingTimeInterval(-60)
        #expect(!ScoringEngine.canSubmitNomination(
            userNominationCount: 0,
            selectionsPerMember: 3,
            uniqueNominationCount: 0,
            slateSize: 12,
            selectionDeadline: past
        ))
        // After removing a selection, a replacement is allowed while under the per-member
        // cap, under slate size, and before the selection deadline.
        let future = Date().addingTimeInterval(7 * 24 * 3600)
        #expect(ScoringEngine.canSubmitNomination(
            userNominationCount: 2,
            selectionsPerMember: 3,
            uniqueNominationCount: 8,
            slateSize: 9,
            selectionDeadline: future
        ))
        #expect(!ScoringEngine.canSubmitNomination(
            userNominationCount: 2,
            selectionsPerMember: 3,
            uniqueNominationCount: 8,
            slateSize: 9,
            selectionDeadline: past
        ))
        // Completing the round does not imply Pickems are open — remake is still allowed.
        #expect(ScoringEngine.isMemberNominationRoundComplete(
            nominationsByUser: ["a": 1, "b": 1],
            memberIds: ["a", "b"],
            selectionsPerMember: 1,
            uniqueNominationCount: 2,
            slateSize: 2
        ))
        #expect(ScoringEngine.canSubmitNomination(
            userNominationCount: 0,
            selectionsPerMember: 1,
            uniqueNominationCount: 1,
            slateSize: 2,
            selectionDeadline: future
        ))
    }

    @Test func expectedSlateSizeIsEitherOr() {
        let member = GroupRules(
            selectionMode: .member,
            selectionsPerMember: 3,
            slateSize: 99,
            pickDeadline: .firstKickoff,
            tieBreaker: .commissionerOverride
        )
        #expect(member.expectedSlateSize(memberCount: 4) == 12)
        #expect(member.expectedSlateSize(memberCount: 1) == 3)
        #expect(member.expectedSlateSize(memberCount: 2) == 6)

        let commissioner = GroupRules(
            selectionMode: .commissioner,
            selectionsPerMember: 3,
            slateSize: 8,
            pickDeadline: .firstKickoff,
            tieBreaker: .commissionerOverride
        )
        #expect(commissioner.expectedSlateSize(memberCount: 4) == 8)
    }

    @Test func memberNominationRoundCompletesWhenAllAtQuota() {
        let byUser = ["a": 3, "b": 3, "c": 3]
        #expect(ScoringEngine.isMemberNominationRoundComplete(
            nominationsByUser: byUser,
            memberIds: ["a", "b", "c"],
            selectionsPerMember: 3,
            uniqueNominationCount: 7,
            slateSize: 9
        ))
        #expect(!ScoringEngine.isMemberNominationRoundComplete(
            nominationsByUser: ["a": 3, "b": 2, "c": 3],
            memberIds: ["a", "b", "c"],
            selectionsPerMember: 3,
            uniqueNominationCount: 7,
            slateSize: 9
        ))
        #expect(ScoringEngine.isMemberNominationRoundComplete(
            nominationsByUser: ["a": 1],
            memberIds: ["a", "b"],
            selectionsPerMember: 3,
            uniqueNominationCount: 9,
            slateSize: 9
        ))
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

    @Test func rankedStandingsInterimOrdersByJoinedAtWhenNoWins() {
        let early = Date(timeIntervalSince1970: 1_000)
        let mid = Date(timeIntervalSince1970: 2_000)
        let late = Date(timeIntervalSince1970: 3_000)
        let entries = [
            StandingEntry(id: "c", displayName: "Zoe", avatarColorHex: "#111111", weeklyWins: 0, weeklyLosses: 0, seasonWins: 0, seasonLosses: 0, rank: 0, isTied: false, joinedAt: late),
            StandingEntry(id: "a", displayName: "Amy", avatarColorHex: "#222222", weeklyWins: 0, weeklyLosses: 0, seasonWins: 0, seasonLosses: 0, rank: 0, isTied: false, joinedAt: early),
            StandingEntry(id: "b", displayName: "Bob", avatarColorHex: "#333333", weeklyWins: 0, weeklyLosses: 0, seasonWins: 0, seasonLosses: 0, rank: 0, isTied: false, joinedAt: mid),
        ]
        let ranked = ScoringEngine.rankedStandings(entries: entries, weekly: true, tieBreaker: .commissionerOverride)
        #expect(ranked.map(\.id) == ["a", "b", "c"])
        #expect(ranked.map(\.rank) == [1, 2, 3])
    }

    @Test func rankedStandingsUsesJoinedAtBeforeDisplayNameAsTiebreaker() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        let entries = [
            StandingEntry(id: "z", displayName: "Zoe", avatarColorHex: "#111111", weeklyWins: 5, weeklyLosses: 2, seasonWins: 5, seasonLosses: 2, rank: 0, isTied: false, joinedAt: early),
            StandingEntry(id: "a", displayName: "Amy", avatarColorHex: "#222222", weeklyWins: 5, weeklyLosses: 2, seasonWins: 5, seasonLosses: 2, rank: 0, isTied: false, joinedAt: late),
        ]
        let ranked = ScoringEngine.rankedStandings(entries: entries, weekly: true, tieBreaker: .commissionerOverride)
        #expect(ranked[0].id == "z")
        #expect(ranked[1].id == "a")
    }

    @Test func rankedStandingsSeasonModeUsesSeasonWinsForInterimGate() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        let entries = [
            StandingEntry(id: "late", displayName: "Late", avatarColorHex: "#111111", weeklyWins: 0, weeklyLosses: 0, seasonWins: 0, seasonLosses: 0, rank: 0, isTied: false, joinedAt: late),
            StandingEntry(id: "early", displayName: "Early", avatarColorHex: "#222222", weeklyWins: 0, weeklyLosses: 0, seasonWins: 0, seasonLosses: 0, rank: 0, isTied: false, joinedAt: early),
        ]
        let interim = ScoringEngine.rankedStandings(entries: entries, weekly: false, tieBreaker: .commissionerOverride)
        #expect(interim.map(\.id) == ["early", "late"])

        var withWins = entries
        withWins[0].seasonWins = 3
        withWins[0].seasonLosses = 1
        withWins[1].seasonWins = 1
        withWins[1].seasonLosses = 3
        let ranked = ScoringEngine.rankedStandings(entries: withWins, weekly: false, tieBreaker: .commissionerOverride)
        #expect(ranked[0].id == "late")
        #expect(ranked[1].id == "early")
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
