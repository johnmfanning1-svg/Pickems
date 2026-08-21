import Foundation
import Testing
@testable import Pickems

@MainActor
struct ScrimmageEngineTests {
    @Test func allSixteenPickCombinationsYieldFourAndOhWithNoPushes() async {
        for mask in 0..<16 {
            let engine = ScrimmageEngine(userDisplayName: "Tester", liveTickInterval: 0)
            engine.advance()

            for (index, game) in engine.games.enumerated() {
                let pickHome = (mask & (1 << index)) != 0
                engine.selectTeam(
                    gameId: game.id,
                    teamId: pickHome ? game.homeTeamId : game.awayTeamId
                )
            }

            engine.submitPicks()
            await engine.runLiveSimulation()

            #expect(engine.userRecord.wins == 4)
            #expect(engine.userRecord.losses == 0)
            #expect(engine.phase == .results)

            for game in engine.games {
                #expect(game.status == .final)
                guard let homeScore = game.homeScore, let awayScore = game.awayScore else {
                    Issue.record("Missing scores for \(game.id)")
                    continue
                }
                let covered = game.coveredTeamId(homeScore: homeScore, awayScore: awayScore)
                #expect(covered != nil)
                #expect(covered == engine.draftPicks[game.id])
            }
        }
    }

    @Test func standingsPutUserFirstAboveBotsWithExpectedRecords() {
        let engine = ScrimmageEngine(userDisplayName: "Alex", liveTickInterval: 0)
        engine.advance()
        for game in engine.games {
            engine.selectTeam(gameId: game.id, teamId: game.homeTeamId)
        }
        engine.submitPicks()

        #expect(engine.standings.count == 4)
        #expect(engine.standings[0].isUser)
        #expect(engine.standings[0].rank == 1)
        #expect(engine.standings[0].wins == 4)
        #expect(engine.standings[0].losses == 0)
        #expect(engine.standings[0].displayName == "Alex")

        let bots = engine.standings.filter { !$0.isUser }
        #expect(bots.map(\.wins) == [3, 2, 1])
        #expect(bots.map(\.losses) == [1, 2, 3])
        #expect(bots.map(\.rank) == [2, 3, 4])
        for bot in bots {
            #expect(engine.standings[0].wins > bot.wins)
        }
    }

    @Test func phaseTransitionsFollowDocumentedOrder() async {
        let engine = ScrimmageEngine(userDisplayName: "Tester", liveTickInterval: 0)
        #expect(engine.phase == .intro)

        engine.advance()
        #expect(engine.phase == .picking)

        // advance() is a no-op while picking / locked / live
        engine.advance()
        #expect(engine.phase == .picking)

        for game in engine.games {
            engine.selectTeam(gameId: game.id, teamId: game.awayTeamId)
        }
        engine.submitPicks()
        #expect(engine.phase == .locked)

        engine.advance()
        #expect(engine.phase == .locked)

        await engine.runLiveSimulation()
        #expect(engine.phase == .results)

        engine.advance()
        #expect(engine.phase == .standings)

        engine.advance()
        #expect(engine.phase == .celebration)

        engine.advance()
        #expect(engine.phase == .celebration)
    }

    @Test func advanceIsNoOpDuringLive() async {
        let engine = ScrimmageEngine(userDisplayName: "Tester", liveTickInterval: 60)
        engine.advance()
        for game in engine.games {
            engine.selectTeam(gameId: game.id, teamId: game.homeTeamId)
        }
        engine.submitPicks()

        let sim = Task { await engine.runLiveSimulation() }
        var sawLive = false
        for _ in 0..<200 {
            if engine.phase == .live {
                sawLive = true
                break
            }
            await Task.yield()
        }
        #expect(sawLive)
        engine.advance()
        #expect(engine.phase == .live)
        sim.cancel()
        _ = await sim.result
    }

    @Test func resetRestoresIntroEmptyPicksAndUnscoredGames() async {
        let engine = ScrimmageEngine(userDisplayName: "Tester", liveTickInterval: 0)
        engine.advance()
        for game in engine.games {
            engine.selectTeam(gameId: game.id, teamId: game.homeTeamId)
        }
        engine.submitPicks()
        await engine.runLiveSimulation()
        engine.advance()

        engine.reset()

        #expect(engine.phase == .intro)
        #expect(engine.draftPicks.isEmpty)
        #expect(engine.standings.isEmpty)
        #expect(engine.userRecord == (0, 0))
        #expect(engine.games.count == 4)
        for game in engine.games {
            #expect(game.status == .scheduled)
            #expect(game.homeScore == nil)
            #expect(game.awayScore == nil)
            #expect(game.winnerTeamId == nil)
        }
    }

    @Test func submitPicksDoesNothingWhenIncomplete() {
        let engine = ScrimmageEngine(userDisplayName: "Tester", liveTickInterval: 0)
        engine.advance()
        engine.selectTeam(gameId: engine.games[0].id, teamId: engine.games[0].homeTeamId)
        #expect(!engine.allPicksMade)

        engine.submitPicks()

        #expect(engine.phase == .picking)
        #expect(engine.standings.isEmpty)
        #expect(engine.userRecord == (0, 0))
        for game in engine.games {
            #expect(game.status == .scheduled)
            #expect(game.homeScore == nil)
        }
    }

    @Test func selectTeamIgnoredOutsidePicking() {
        let engine = ScrimmageEngine(userDisplayName: "Tester", liveTickInterval: 0)
        let game = engine.games[0]
        engine.selectTeam(gameId: game.id, teamId: game.homeTeamId)
        #expect(engine.draftPicks.isEmpty)

        engine.advance()
        engine.selectTeam(gameId: game.id, teamId: game.homeTeamId)
        #expect(engine.draftPicks[game.id] == game.homeTeamId)
    }

    @Test func scrimmageDataHasHalfPointSpreadsAndThreeBots() {
        let games = ScrimmageData.makeGames()
        #expect(games.count == 4)
        for game in games {
            #expect(game.id == game.espnEventId)
            #expect(game.homeTeamLogoURL == nil)
            #expect(game.awayTeamLogoURL == nil)
            #expect(game.status == .scheduled)
            let fraction = abs(game.spread).truncatingRemainder(dividingBy: 1)
            #expect(fraction == 0.5)
        }

        #expect(ScrimmageData.bots.count == 3)
        #expect(ScrimmageData.bots.map(\.agreesWithUserCount) == [3, 2, 1])
    }
}
