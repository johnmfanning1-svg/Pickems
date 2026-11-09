import Foundation
import Testing
@testable import Pickems

struct LiveActivityContentTests {
    @Test func liveGamesThenNextKickoffThenFinals() {
        let state = LiveActivityContent.build(
            games: [
                game("final-early", status: .final, home: 21, away: 14, kickoff: 1),
                game("live-late", status: .inProgress, home: 10, away: 7, kickoff: 3),
                game("live-early", status: .inProgress, home: 14, away: 14, kickoff: 2),
                game("next", status: .scheduled, kickoff: 4),
                game("later", status: .scheduled, kickoff: 5),
            ],
            picks: picked("final-early", "live-late", "live-early", "next", "later"),
            pickMode: .ats
        )
        #expect(state.picks.map(\.gameId) == ["live-early", "live-late", "next"])
        #expect(state.picks.map(\.phase) == ["live", "live", "upcoming"])
    }

    @Test func capsTheLockScreenAtThreePicks() {
        let games = (0..<12).map { index in
            game("g\(index)", status: .inProgress, home: 7, away: 0, kickoff: Double(index))
        }
        let state = LiveActivityContent.build(
            games: games,
            picks: Dictionary(uniqueKeysWithValues: games.map { ($0.id, "HOME") }),
            pickMode: .ats
        )
        #expect(state.picks.map(\.gameId) == ["g0", "g1", "g2"])
    }

    @Test func leavesOutGamesTheViewerDidNotPick() {
        let state = LiveActivityContent.build(
            games: [
                game("mine", status: .inProgress, home: 17, away: 10, kickoff: 2),
                game("theirs", status: .inProgress, home: 28, away: 21, kickoff: 1),
                game("blank", status: .final, home: 10, away: 7, kickoff: 3),
                game("stranger", status: .final, home: 3, away: 0, kickoff: 4),
            ],
            picks: ["mine": "HOME", "blank": "   ", "stranger": "neither"],
            pickMode: .ats
        )
        #expect(state.picks.map(\.gameId) == ["mine"])
        #expect(state.picks[0].picked == "HOME")
        #expect(!state.picks.contains { $0.picked == "AWAY" && $0.gameId == "theirs" })
    }

    @Test func nextKickoffIsTheViewersPickNotAnEarlierSlateGame() {
        let state = LiveActivityContent.build(
            games: [
                game("slate", status: .scheduled, kickoff: 1),
                game("mine", status: .scheduled, kickoff: 2),
            ],
            picks: ["mine": "AWAY"],
            pickMode: .ats
        )
        #expect(state.picks.map(\.gameId) == ["mine"])
        #expect(state.picks[0].picked == "AWAY")
        #expect(state.picks[0].opponent == "HOME")
        #expect(state.picks[0].phase == "upcoming")
        #expect(state.picks[0].pickedScore == nil)
        #expect(state.picks[0].result == "pending")
    }

    @Test func recentFinalsAreTheLatestKickoffs() {
        let state = LiveActivityContent.build(
            games: [
                game("noon", status: .final, home: 21, away: 17, kickoff: 1),
                game("afternoon", status: .final, home: 14, away: 24, kickoff: 2),
                game("night", status: .final, home: 31, away: 10, kickoff: 3),
                game("late", status: .final, home: 7, away: 3, kickoff: 4),
            ],
            picks: picked("noon", "afternoon", "night", "late"),
            pickMode: .ats
        )
        #expect(state.picks.map(\.gameId) == ["late", "night", "afternoon"])
    }

    @Test func atsLiveCoverTrailAndPush() {
        let state = LiveActivityContent.build(
            games: [
                game("cover", status: .inProgress, home: 31, away: 20, kickoff: 1),
                game("trail", status: .inProgress, home: 24, away: 20, kickoff: 2),
                game("push", status: .inProgress, home: 27, away: 20, kickoff: 3),
            ],
            picks: ["cover": "HOME", "trail": "HOME", "push": "HOME"],
            pickMode: .ats
        )
        #expect(state.picks.map(\.result) == ["covering", "trailing", "push"])
        #expect(state.picks.map(\.resultLabel) == ["Covering", "Trailing", "Pushing"])
        #expect(state.picks[0].pickedScore == 31)
        #expect(state.picks[0].opponentScore == 20)
        #expect(state.picks[1].pickedScore == 24)
        #expect(state.picks[1].opponentScore == 20)
    }

    @Test func atsFinalWonLostAndPush() {
        let state = LiveActivityContent.build(
            games: [
                game("won", status: .final, home: 31, away: 20, kickoff: 3),
                game("lost", status: .final, home: 24, away: 20, kickoff: 2),
                game("push", status: .final, home: 27, away: 20, kickoff: 1),
            ],
            picks: picked("won", "lost", "push"),
            pickMode: .ats
        )
        #expect(state.picks.map(\.resultLabel) == ["Won", "Lost", "Push"])
        #expect(state.picks.map(\.result) == ["won", "lost", "push"])
    }

    @Test func straightUpGradesTheScoreNotTheSpread() {
        let live = LiveActivityContent.build(
            games: [
                game("su", status: .inProgress, home: 24, away: 20, kickoff: 1),
                game("tie", status: .inProgress, home: 17, away: 17, kickoff: 2),
            ],
            picks: picked("su", "tie"),
            pickMode: .straightUp
        )
        #expect(live.picks.map(\.resultLabel) == ["Winning", "Tied"])
        let finals = LiveActivityContent.build(
            games: [
                game("su", status: .final, home: 24, away: 20, kickoff: 2),
                game("tie", status: .final, home: 17, away: 17, kickoff: 1),
            ],
            picks: picked("su", "tie"),
            pickMode: .straightUp
        )
        #expect(finals.picks.map(\.resultLabel) == ["Won", "Push"])
        let ats = LiveActivityContent.build(
            games: [game("su", status: .final, home: 24, away: 20, kickoff: 1)],
            picks: ["su": "HOME"],
            pickMode: .ats
        )
        #expect(ats.picks[0].resultLabel == "Lost")
    }

    @Test func weeklyRecordCountsMissesPushesAndConfidence() {
        let missed = LiveActivityContent.build(
            games: [game("skip", status: .final, home: 21, away: 14, kickoff: 1)],
            picks: [:],
            pickMode: .ats
        )
        #expect(missed.weeklyWins == 0)
        #expect(missed.weeklyLosses == 1)
        #expect(missed.picks.isEmpty)
        #expect(missed.recordText == "0-1")

        let doubled = LiveActivityContent.build(
            games: [game("star", status: .final, home: 31, away: 20, kickoff: 1)],
            picks: ["star": "HOME"],
            pickMode: .ats,
            confidenceGameId: "star"
        )
        #expect(doubled.weeklyWins == 2)
        #expect(doubled.recordText == "2-0")

        let pushed = LiveActivityContent.build(
            games: [game("push", status: .final, home: 27, away: 20, kickoff: 1)],
            picks: ["push": "HOME"],
            pickMode: .ats
        )
        #expect(pushed.weeklyPushes == 1)
        #expect(pushed.recordText == "0-0-1")
        #expect(pushed.rankText == nil)

        let penalized = LiveActivityContent.build(
            games: [game("late", status: .final, home: 31, away: 20, kickoff: 1)],
            picks: ["late": "HOME"],
            pickMode: .ats,
            submittedAt: Date(timeIntervalSince1970: 20),
            deadline: Date(timeIntervalSince1970: 10),
            latePenaltyWins: 1,
            rank: 1,
            rankBoardDecidedGames: 1
        )
        #expect(penalized.weeklyWins == 0)
        #expect(penalized.rank == nil)
    }

    @Test func hidesRankAtZeroAndZeroAndWhenTheBoardHasNoDecision() {
        let fake = LiveActivityContent.build(
            games: [game("live", status: .inProgress, home: 7, away: 0, kickoff: 1)],
            picks: ["live": "HOME"],
            pickMode: .ats,
            rank: 1,
            rankBoardDecidedGames: 0
        )
        #expect(fake.weeklyWins == 0)
        #expect(fake.rank == nil)
        #expect(fake.rankText == nil)

        let aheadOfTheBoard = LiveActivityContent.build(
            games: [game("final", status: .final, home: 31, away: 20, kickoff: 1)],
            picks: ["final": "HOME"],
            pickMode: .ats,
            rank: 1,
            rankBoardDecidedGames: 0
        )
        #expect(aheadOfTheBoard.weeklyWins == 1)
        #expect(aheadOfTheBoard.rank == nil)
        #expect(aheadOfTheBoard.rankText == nil)
    }

    @Test func showsAnHonestRankIncludingTies() {
        let ranked = LiveActivityContent.build(
            games: [game("final", status: .final, home: 31, away: 20, kickoff: 1)],
            picks: ["final": "HOME"],
            pickMode: .ats,
            rank: 2,
            rankBoardDecidedGames: 1
        )
        #expect(ranked.rank == 2)
        #expect(ranked.rankTied == false)
        #expect(ranked.rankText == "#2")

        let tied = LiveActivityContent.build(
            games: [game("final", status: .final, home: 31, away: 20, kickoff: 1)],
            picks: ["final": "HOME"],
            pickMode: .ats,
            rank: 1,
            rankTied: true,
            rankBoardDecidedGames: 1
        )
        #expect(tied.rankText == "T-#1")
    }

    @Test func lockedOrLivePickingWeekRuns() {
        #expect(LiveActivityContent.shouldRun(weekStatus: .locked, pickingHasLiveGame: false))
        #expect(LiveActivityContent.shouldRun(weekStatus: .picking, pickingHasLiveGame: true))
    }

    @Test func otherWeekStatesEndTheActivity() {
        #expect(!LiveActivityContent.shouldRun(weekStatus: .picking, pickingHasLiveGame: false))
        #expect(!LiveActivityContent.shouldRun(weekStatus: .scored, pickingHasLiveGame: true))
        #expect(!LiveActivityContent.shouldRun(weekStatus: .selection, pickingHasLiveGame: true))
        #expect(!LiveActivityContent.shouldRun(weekStatus: nil, pickingHasLiveGame: true))
    }

    @Test func tapOpensTheLiveGameOtherwiseTheWeek() throws {
        let live = LiveActivityPick(
            gameId: "live-game",
            picked: "OSU",
            opponent: "MICH",
            pickedScore: 21,
            opponentScore: 17,
            phase: "live",
            result: "covering",
            resultLabel: "Covering",
            kickoffUnix: 2
        )
        let final = LiveActivityPick(
            gameId: "final-game",
            picked: "ALA",
            opponent: "UGA",
            pickedScore: 28,
            opponentScore: 14,
            phase: "final",
            result: "won",
            resultLabel: "Won",
            kickoffUnix: 1
        )
        let liveURL = try #require(LiveActivityDestination.url(
            groupId: "league 1",
            weekId: "2026-W6",
            picks: [final, live]
        ))
        #expect(DeepLinkRouter.parse(url: liveURL) == .openGame(
            groupId: "league 1",
            weekId: "2026-W6",
            gameId: "live-game"
        ))
        let weekURL = try #require(LiveActivityDestination.url(groupId: "league-1", weekId: "2026-W6", picks: []))
        #expect(DeepLinkRouter.parse(url: weekURL) == .openWeekPickems(groupId: "league-1", weekId: "2026-W6"))
        #expect(LiveActivityDestination.url(groupId: " ", weekId: "2026-W6", gameId: nil) == nil)
    }

    @Test func legacyPayloadDropsAFakeRank() throws {
        let fake = try JSONDecoder().decode(
            PickemsLiveAttributes.ContentState.self,
            from: Data(#"{"weeklyWins":0,"weeklyLosses":0,"rank":1,"totalPlayers":8,"nextGameLabel":"OSU @ MICH","updatedAt":700000000}"#.utf8)
        )
        #expect(fake.rank == nil)
        #expect(fake.rankText == nil)
        #expect(fake.picks.isEmpty)
        #expect(fake.contentVersion == 0)

        let decided = try JSONDecoder().decode(
            PickemsLiveAttributes.ContentState.self,
            from: Data(#"{"weeklyWins":2,"weeklyLosses":1,"rank":3,"totalPlayers":8,"nextGameLabel":"OSU @ MICH","updatedAt":700000000}"#.utf8)
        )
        #expect(decided.rank == 3)
        #expect(decided.contentVersion == 0)
        #expect(decided.rankText == "#3")
    }

    @Test func pushJSONMatchesTheServerContract() throws {
        let state = LiveActivityContent.build(
            games: [
                game("next", status: .scheduled, kickoff: 1_700_000_100),
                game("final", status: .final, home: 31, away: 20, kickoff: 1_700_000_000),
            ],
            picks: picked("next", "final"),
            pickMode: .ats,
            rank: 1,
            rankBoardDecidedGames: 1,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let roundTrip = try JSONDecoder().decode(
            PickemsLiveAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        )
        #expect(roundTrip == state)
        #expect(roundTrip.picks[0].pickedScore == nil)
        #expect(roundTrip.picks[1].pickedScore == 31)
        let encoded = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(encoded.contains("\"contentVersion\":2"))
        #expect(encoded.contains("\"rank\":1"))
        #expect(encoded.contains("\"pickedScore\":31"))

        let hidden = LiveActivityContent.build(
            games: [game("live", status: .inProgress, home: 0, away: 0, kickoff: 1)],
            picks: ["live": "HOME"],
            pickMode: .ats,
            rank: 1
        )
        let hiddenJSON = String(decoding: try JSONEncoder().encode(hidden), as: UTF8.self)
        #expect(!hiddenJSON.contains("\"rank\":"))

        let server = Data("""
        {"weeklyWins":1,"weeklyLosses":0,"weeklyPushes":0,"rank":2,"rankTied":true,"picks":[{"gameId":"g","picked":"OSU","opponent":"MICH","pickedScore":24,"opponentScore":17,"phase":"live","result":"covering","resultLabel":"Covering","kickoffUnix":1700000000}],"updatedAt":1700000500,"contentVersion":2}
        """.utf8)
        let decoded = try JSONDecoder().decode(PickemsLiveAttributes.ContentState.self, from: server)
        #expect(decoded.rankText == "T-#2")
        #expect(decoded.picks[0].picked == "OSU")
        #expect(decoded.picks[0].pickedScore == 24)
        #expect(decoded.contentVersion == 2)
    }

    @Test func activityKeyJoinsLeagueAndWeek() {
        #expect(LiveActivitySchema.activityKey(groupId: "league-1", weekId: "2026-W6") == "league-1|2026-W6")
        #expect(LiveActivitySchema.version == 2)
        #expect(LiveActivitySchema.maxPicks == 3)
    }
}

private func game(
    _ id: String,
    status: SlateGame.GameStatus,
    home: Int? = nil,
    away: Int? = nil,
    kickoff: Double,
    spread: Double = 7
) -> SlateGame {
    SlateGame(
        id: id,
        espnEventId: id,
        homeTeamId: "HOME",
        homeTeamName: "Home",
        homeTeamAbbreviation: "HOME",
        homeTeamLogoURL: nil,
        awayTeamId: "AWAY",
        awayTeamName: "Away",
        awayTeamAbbreviation: "AWAY",
        awayTeamLogoURL: nil,
        spread: spread,
        spreadTeamId: "HOME",
        kickoff: Date(timeIntervalSince1970: kickoff),
        status: status,
        homeScore: home,
        awayScore: away,
        winnerTeamId: nil
    )
}

private func picked(_ ids: String...) -> [String: String] {
    Dictionary(uniqueKeysWithValues: ids.map { ($0, "HOME") })
}
