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

    @Test func boardStatusLiveCoveringAndTrailing() {
        let live = boardGame(status: .inProgress, homeScore: 21, awayScore: 10)
        #expect(ScoringEngine.pickBoardStatus(pickedTeamId: "home", game: live) == .covering)
        #expect(ScoringEngine.pickBoardStatus(pickedTeamId: "away", game: live) == .trailing)
        #expect(ScoringEngine.pickBoardStatus(pickedTeamId: nil, game: live) == .none)
    }

    @Test func boardStatusFinalWonLostAndPush() {
        let final = boardGame(status: .final, homeScore: 28, awayScore: 17)
        #expect(ScoringEngine.pickBoardStatus(pickedTeamId: "home", game: final) == .won)
        #expect(ScoringEngine.pickBoardStatus(pickedTeamId: "away", game: final) == .lost)
        let push = boardGame(status: .final, homeScore: 24, awayScore: 17)
        #expect(ScoringEngine.pickBoardStatus(pickedTeamId: "home", game: push) == .push)
        let scheduled = boardGame(status: .scheduled, homeScore: nil, awayScore: nil)
        #expect(ScoringEngine.pickBoardStatus(pickedTeamId: "home", game: scheduled) == .pending)
    }

    private func boardGame(
        status: SlateGame.GameStatus,
        homeScore: Int?,
        awayScore: Int?
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
            spread: 7,
            spreadTeamId: "home",
            kickoff: Date(),
            status: status,
            homeScore: homeScore,
            awayScore: awayScore,
            winnerTeamId: status == .final ? "home" : nil
        )
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

    @Test func rankedStandingsTiesEqualWinsRegardlessOfBattingAverage() {
        let entries = [
            StandingEntry(id: "a", displayName: "A", avatarColorHex: "#DC2626", weeklyWins: 4, weeklyLosses: 4, seasonWins: 10, seasonLosses: 5, rank: 0, isTied: false),
            StandingEntry(id: "b", displayName: "B", avatarColorHex: "#3366CC", weeklyWins: 4, weeklyLosses: 2, seasonWins: 8, seasonLosses: 7, rank: 0, isTied: false),
        ]
        let ranked = ScoringEngine.rankedStandings(entries: entries, weekly: true, tieBreaker: .commissionerOverride)
        #expect(ranked.map(\.id) == ["a", "b"])
        #expect(ranked.map(\.rank) == [1, 1])
        #expect(ranked[1].isTied)
    }

    @Test func rankedStandingsOrdersByMostWinsNotBattingAverage() {
        let entries = [
            StandingEntry(id: "late", displayName: "Late", avatarColorHex: "#111111", weeklyWins: 8, weeklyLosses: 0, seasonWins: 8, seasonLosses: 0, rank: 0, isTied: false),
            StandingEntry(id: "vet", displayName: "Veteran", avatarColorHex: "#222222", weeklyWins: 10, weeklyLosses: 10, seasonWins: 10, seasonLosses: 10, rank: 0, isTied: false),
        ]
        let weekly = ScoringEngine.rankedStandings(entries: entries, weekly: true, tieBreaker: .commissionerOverride)
        #expect(weekly.map(\.id) == ["vet", "late"])
        let season = ScoringEngine.rankedStandings(entries: entries, weekly: false, tieBreaker: .commissionerOverride)
        #expect(season.map(\.id) == ["vet", "late"])
    }

    @Test func missedPickOnFinalSlateGameIsALoss() {
        let cover = boardGame(status: .final, homeScore: 28, awayScore: 17)
        let miss = SlateGame(
            id: "2",
            espnEventId: "2",
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
            homeScore: 10,
            awayScore: 21,
            winnerTeamId: "away"
        )
        let partial = ScoringEngine.scorePicks(picks: ["1": "home"], games: [cover, miss])
        #expect(partial.wins == 1)
        #expect(partial.losses == 1)
        let satOut = ScoringEngine.scorePicks(picks: [:], games: [cover, miss])
        #expect(satOut.wins == 0)
        #expect(satOut.losses == 2)
        let push = boardGame(status: .final, homeScore: 24, awayScore: 17)
        let missedPush = ScoringEngine.scorePicks(picks: [:], games: [push])
        #expect(missedPush.losses == 1)
        #expect(missedPush.pushes == 0)
        let scheduled = boardGame(status: .scheduled, homeScore: nil, awayScore: nil)
        let beforeKickoff = ScoringEngine.scorePicks(picks: [:], games: [scheduled])
        #expect(beforeKickoff.wins == 0)
        #expect(beforeKickoff.losses == 0)
        #expect(beforeKickoff.pushes == 0)
        let missedConfidence = ScoringEngine.scorePicks(picks: [:], games: [cover], confidenceGameId: "1")
        #expect(missedConfidence.losses == 1)
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

    @Test func commissionerOverrideOrderBreaksEqualRecords() {
        let entries = [
            StandingEntry(id: "a", displayName: "A", avatarColorHex: "#DC2626", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 0, isTied: false),
            StandingEntry(id: "b", displayName: "B", avatarColorHex: "#3366CC", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 0, isTied: false),
        ]
        let ranked = ScoringEngine.rankedStandings(
            entries: entries,
            weekly: true,
            tieBreaker: .commissionerOverride,
            tieBreakOrder: ["b"]
        )
        #expect(ranked.map(\.id) == ["b", "a"])
        #expect(ranked.map(\.rank) == [1, 2])
        #expect(ranked.allSatisfy { !$0.isTied })
    }

    @Test func commissionerOverrideThreeWayLeavesRemainingTied() {
        let entries = [
            StandingEntry(id: "a", displayName: "Amy", avatarColorHex: "#DC2626", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 0, isTied: false),
            StandingEntry(id: "b", displayName: "Bo", avatarColorHex: "#3366CC", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 0, isTied: false),
            StandingEntry(id: "c", displayName: "Cam", avatarColorHex: "#22AA44", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 0, isTied: false),
        ]
        let ranked = ScoringEngine.rankedStandings(
            entries: entries,
            weekly: true,
            tieBreaker: .commissionerOverride,
            tieBreakOrder: ["a"]
        )
        #expect(ranked[0].id == "a")
        #expect(ranked[0].rank == 1)
        #expect(!ranked[0].isTied)
        #expect(Set(ranked.dropFirst().map(\.rank)) == [2])
        #expect(ranked[2].isTied)
        let groups = ScoringEngine.unresolvedWeeklyTieGroups(from: ranked)
        #expect(groups.count == 1)
        #expect(Set(groups[0].map(\.id)) == ["b", "c"])
    }

    @Test func rankTieBreakGroupWritesFullOrderAfterExistingGroups() {
        let leftover = ScoringEngine.rankTieBreakGroup(["c", "a", "b"], in: ["x", "a"])
        #expect(leftover == ["x", "c", "a", "b"])
        #expect(ScoringEngine.rankTieBreakGroup(["a"], in: ["z"]) == ["z"])
        #expect(ScoringEngine.rankTieBreakGroup(["c", "a", "c", "b"], in: []) == ["c", "a", "b"])
    }

    @Test func commissionerOverrideFullGroupOrderClearsTie() {
        let entries = [
            StandingEntry(id: "a", displayName: "Amy", avatarColorHex: "#DC2626", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 0, isTied: false),
            StandingEntry(id: "b", displayName: "Bo", avatarColorHex: "#3366CC", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 0, isTied: false),
            StandingEntry(id: "c", displayName: "Cam", avatarColorHex: "#22AA44", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 0, isTied: false),
            StandingEntry(id: "d", displayName: "Dee", avatarColorHex: "#AA22AA", weeklyWins: 5, weeklyLosses: 2, seasonWins: 5, seasonLosses: 2, rank: 0, isTied: false),
            StandingEntry(id: "e", displayName: "Eli", avatarColorHex: "#22AAAA", weeklyWins: 5, weeklyLosses: 2, seasonWins: 5, seasonLosses: 2, rank: 0, isTied: false),
        ]
        let ranked = ScoringEngine.rankedStandings(
            entries: entries,
            weekly: true,
            tieBreaker: .commissionerOverride,
            tieBreakOrder: ["c", "a", "b"]
        )
        #expect(ranked.prefix(3).map(\.id) == ["c", "a", "b"])
        #expect(ranked.prefix(3).map(\.rank) == [1, 2, 3])
        #expect(ranked.prefix(3).allSatisfy { !$0.isTied })
        #expect(Set(ranked.suffix(2).map(\.id)) == ["d", "e"])
        #expect(Set(ranked.suffix(2).map(\.rank)) == [4])
        #expect(ranked[4].isTied)
        let groups = ScoringEngine.unresolvedWeeklyTieGroups(from: ranked)
        #expect(groups.count == 1)
        #expect(Set(groups[0].map(\.id)) == ["d", "e"])
    }

    @Test func unresolvedWeeklyTieGroupsPreservesRankedOrder() {
        let ranked = [
            StandingEntry(id: "c", displayName: "Cam", avatarColorHex: "#22AA44", weeklyWins: 8, weeklyLosses: 5, seasonWins: 8, seasonLosses: 5, rank: 1, isTied: false),
            StandingEntry(id: "a", displayName: "Amy", avatarColorHex: "#DC2626", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 1, isTied: true),
            StandingEntry(id: "b", displayName: "Bo", avatarColorHex: "#3366CC", weeklyWins: 8, weeklyLosses: 3, seasonWins: 8, seasonLosses: 3, rank: 1, isTied: true),
        ]
        let groups = ScoringEngine.unresolvedWeeklyTieGroups(from: ranked)
        #expect(groups.count == 1)
        #expect(groups[0].map(\.id) == ["c", "a", "b"])
    }

    @Test func unresolvedWeeklyTieGroupsSkipsZeroRecords() {
        let ranked = [
            StandingEntry(id: "a", displayName: "A", avatarColorHex: "#DC2626", weeklyWins: 0, weeklyLosses: 0, seasonWins: 0, seasonLosses: 0, rank: 1, isTied: false),
            StandingEntry(id: "b", displayName: "B", avatarColorHex: "#3366CC", weeklyWins: 0, weeklyLosses: 0, seasonWins: 0, seasonLosses: 0, rank: 1, isTied: true),
        ]
        #expect(ScoringEngine.unresolvedWeeklyTieGroups(from: ranked).isEmpty)
    }

    @Test func commissionerTieBreakHiddenUntilWeekIsFinal() {
        let week = WeekSummary(
            id: "2026-W3",
            seasonYear: 2026,
            weekNumber: 3,
            status: .selection,
            slateSize: 2,
            selectionMode: .member,
            selectionsPerMember: 1,
            nominationCount: 0
        )
        let live = SlateGame(
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
            status: .inProgress,
            homeScore: 14,
            awayScore: 7,
            winnerTeamId: nil
        )
        let final = SlateGame(
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
        #expect(!ScoringEngine.canShowCommissionerTieBreak(
            week: week,
            games: [final],
            tieBreaker: .commissionerOverride
        ))
        var scored = week
        scored.status = .scored
        #expect(ScoringEngine.canShowCommissionerTieBreak(
            week: scored,
            games: [],
            tieBreaker: .commissionerOverride
        ))
        var locked = week
        locked.status = .locked
        #expect(!ScoringEngine.canShowCommissionerTieBreak(
            week: locked,
            games: [live],
            tieBreaker: .commissionerOverride
        ))
        #expect(ScoringEngine.canShowCommissionerTieBreak(
            week: locked,
            games: [final],
            tieBreaker: .commissionerOverride
        ))
        #expect(!ScoringEngine.canShowCommissionerTieBreak(
            week: scored,
            games: [final],
            tieBreaker: .headToHead
        ))
    }

    @Test func seasonRankingIgnoresWeeklyTieBreakOrder() {
        let entries = [
            StandingEntry(id: "a", displayName: "A", avatarColorHex: "#DC2626", weeklyWins: 1, weeklyLosses: 0, seasonWins: 4, seasonLosses: 2, rank: 0, isTied: false),
            StandingEntry(id: "b", displayName: "B", avatarColorHex: "#3366CC", weeklyWins: 0, weeklyLosses: 1, seasonWins: 4, seasonLosses: 2, rank: 0, isTied: false),
        ]
        let ranked = ScoringEngine.rankedStandings(
            entries: entries,
            weekly: false,
            tieBreaker: .commissionerOverride,
            tieBreakOrder: ["b"]
        )
        #expect(ranked[0].rank == 1)
        #expect(ranked[1].rank == 1)
        #expect(ranked[1].isTied)
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

    @Test func straightUpIgnoresSpreadAndPushesOnTie() {
        let atsPush = boardGame(status: .final, homeScore: 24, awayScore: 17)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: atsPush) == nil)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: atsPush, pickMode: .straightUp) == true)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "away", game: atsPush, pickMode: .straightUp) == false)

        let tie = boardGame(status: .final, homeScore: 21, awayScore: 21)
        #expect(ScoringEngine.isPickCorrect(pickedTeamId: "home", game: tie, pickMode: .straightUp) == nil)
        #expect(ScoringEngine.pickBoardStatus(pickedTeamId: "home", game: tie, pickMode: .straightUp) == .push)
        #expect(ScoringEngine.scorePicks(picks: ["1": "home"], games: [atsPush], pickMode: .straightUp).wins == 1)
        #expect(ScoringEngine.scorePicks(picks: [:], games: [atsPush], pickMode: .straightUp).losses == 1)
        #expect(PickBoardStatus.covering.label(for: .straightUp) == "Winning")
        #expect(PickBoardStatus.trailing.label(for: .straightUp) == "Losing")
        #expect(PickBoardStatus.covering.label(for: .ats) == "Covering")
    }

    @Test func latePickPenaltySubtractsWinsAfterDeadline() {
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
        let deadline = Date(timeIntervalSince1970: 1_000)
        let late = ScoringEngine.scorePicks(
            picks: ["1": "home"],
            games: [game],
            submittedAt: Date(timeIntervalSince1970: 2_000),
            deadline: deadline,
            latePenaltyWins: 1
        )
        let onTime = ScoringEngine.scorePicks(
            picks: ["1": "home"],
            games: [game],
            submittedAt: Date(timeIntervalSince1970: 500),
            deadline: deadline,
            latePenaltyWins: 1
        )
        #expect(late.wins == 0)
        #expect(onTime.wins == 1)
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
            games: [game],
            tieBreakOrder: ["c"]
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
        #expect(rules.pickMode == .ats)
    }

    @Test func missingPickModeDecodesAsATS() throws {
        let json = Data(#"""
        {
          "selectionMode": "member",
          "selectionsPerMember": 3,
          "slateSize": 12,
          "pickDeadline": "firstKickoff",
          "tieBreaker": "commissionerOverride"
        }
        """#.utf8)
        let rules = try JSONDecoder().decode(GroupRules.self, from: json)
        #expect(rules.pickMode == .ats)
        #expect(rules.showsSpreads == true)
    }

    @Test func straightUpEncodesAndHidesSpreads() throws {
        var rules = GroupRules.default
        rules.pickMode = .straightUp
        let encoded = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode(GroupRules.self, from: encoded)
        #expect(decoded.pickMode == .straightUp)
        #expect(decoded.showsSpreads == false)
        #expect(PickMode.straightUp.pickemsSectionTitle == "Straight Up Pickems")
    }

    @Test func missingWeekPickModeInheritsLeagueType() throws {
        let json = Data(#"""
        {
          "id": "2026-W3",
          "seasonYear": 2026,
          "weekNumber": 3,
          "status": "selection",
          "slateSize": 12,
          "selectionMode": "member",
          "selectionsPerMember": 3,
          "nominationCount": 0
        }
        """#.utf8)
        let week = try JSONDecoder().decode(WeekSummary.self, from: json)
        #expect(week.pickMode == nil)
        #expect(week.resolvedPickMode(leagueMode: .ats) == .ats)
        #expect(week.resolvedPickMode(leagueMode: .straightUp) == .straightUp)
    }

    @Test func weekStraightUpOverrideDoesNotDowngradeStraightUpLeagues() {
        var week = WeekSummary(
            id: "2026-W4",
            seasonYear: 2026,
            weekNumber: 4,
            status: .selection,
            slateSize: 12,
            selectionMode: .member,
            selectionsPerMember: 3,
            nominationCount: 0,
            pickMode: .straightUp
        )
        #expect(week.resolvedPickMode(leagueMode: .ats) == .straightUp)
        week.pickMode = .ats
        #expect(week.resolvedPickMode(leagueMode: .straightUp) == .straightUp)
    }
}
