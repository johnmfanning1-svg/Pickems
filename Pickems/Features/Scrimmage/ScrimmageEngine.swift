import Foundation

@MainActor
@Observable
final class ScrimmageEngine {
    private(set) var phase: ScrimmagePhase = .intro
    private(set) var games: [SlateGame]
    /// ATS Pickems keyed by game id.
    private(set) var draftPicks: [String: String] = [:]
    /// Optional 2x confidence game (product: one confidence Pickem per week).
    private(set) var confidenceGameId: String?
    private(set) var standings: [ScrimmageStanding] = []
    let userDisplayName: String

    private let liveTickInterval: TimeInterval
    private var finalScores: [String: (home: Int, away: Int)] = [:]

    private static let liveTickCount = 5
    private static let userStandingId = "scrimmage-user"

    var allPickemsMade: Bool {
        games.allSatisfy { draftPicks[$0.id] != nil }
    }

    /// Legacy alias used by older call sites / tests.
    var allPicksMade: Bool { allPickemsMade }

    var userRecord: (wins: Int, losses: Int) {
        guard let user = standings.first(where: \.isUser) else { return (0, 0) }
        return (user.wins, user.losses)
    }

    init(userDisplayName: String, liveTickInterval: TimeInterval = 0.6) {
        self.userDisplayName = userDisplayName
        self.liveTickInterval = liveTickInterval
        self.games = ScrimmageData.makeGames()
    }

    func advance() {
        switch phase {
        case .intro:
            phase = .selection
        case .selection:
            phase = .picking
        case .results:
            phase = .standings
        case .standings:
            phase = .celebration
        case .picking, .locked, .live, .celebration:
            break
        }
    }

    /// Selects or clears a Pickem. Pass an empty `teamId` to clear (matches `GamePickRow`).
    func selectTeam(gameId: String, teamId: String) {
        guard phase == .picking else { return }
        guard games.contains(where: { $0.id == gameId }) else { return }
        if teamId.isEmpty {
            draftPicks.removeValue(forKey: gameId)
            if confidenceGameId == gameId {
                confidenceGameId = nil
            }
        } else {
            draftPicks[gameId] = teamId
        }
    }

    func toggleConfidence(gameId: String) {
        guard phase == .picking else { return }
        guard draftPicks[gameId] != nil else { return }
        confidenceGameId = confidenceGameId == gameId ? nil : gameId
    }

    func submitPickems() {
        guard phase == .picking, allPickemsMade else { return }

        var scores: [String: (home: Int, away: Int)] = [:]
        for (index, game) in games.enumerated() {
            guard let pickedTeamId = draftPicks[game.id] else { continue }
            let pair = Self.riggedScores(for: game, pickedTeamId: pickedTeamId, gameIndex: index)
            assert(game.coveredTeamId(homeScore: pair.home, awayScore: pair.away) == pickedTeamId)
            scores[game.id] = pair
        }
        finalScores = scores
        standings = Self.makeStandings(userDisplayName: userDisplayName, slateSize: games.count)
        phase = .locked
    }

    /// Legacy alias.
    func submitPicks() { submitPickems() }

    func runLiveSimulation() async {
        guard phase == .locked else { return }
        phase = .live

        let tickCount = Self.liveTickCount
        for tick in 1...tickCount {
            let isFinalTick = tick == tickCount
            let fraction = Double(tick) / Double(tickCount)

            games = games.map { game in
                var updated = game
                guard let finals = finalScores[game.id] else { return updated }

                if isFinalTick {
                    updated.homeScore = finals.home
                    updated.awayScore = finals.away
                    updated.status = .final
                    updated.winnerTeamId = finals.home == finals.away
                        ? nil
                        : (finals.home > finals.away ? game.homeTeamId : game.awayTeamId)
                } else {
                    updated.homeScore = Int((Double(finals.home) * fraction).rounded())
                    updated.awayScore = Int((Double(finals.away) * fraction).rounded())
                    updated.status = .inProgress
                    updated.winnerTeamId = nil
                }
                return updated
            }

            if !isFinalTick, liveTickInterval > 0 {
                do {
                    try await Task.sleep(for: .seconds(liveTickInterval))
                } catch {
                    return
                }
            }
        }

        phase = .results
    }

    func reset() {
        phase = .intro
        draftPicks = [:]
        confidenceGameId = nil
        standings = []
        finalScores = [:]
        games = ScrimmageData.makeGames()
    }

    /// Builds final scores so the user's Pickem always covers.
    private static func riggedScores(
        for game: SlateGame,
        pickedTeamId: String,
        gameIndex: Int
    ) -> (home: Int, away: Int) {
        let baseLosingScores = [17, 20, 24, 21]
        let loserScore = baseLosingScores[gameIndex % baseLosingScores.count]
        let pickedFavorite = pickedTeamId == game.spreadTeamId

        let margin: Int
        if pickedFavorite {
            margin = Int(abs(game.spread).rounded(.up)) + 3
        } else {
            margin = 3 + (gameIndex % 3)
        }

        let winnerScore = loserScore + margin
        if pickedTeamId == game.homeTeamId {
            return (winnerScore, loserScore)
        }
        return (loserScore, winnerScore)
    }

    private static func makeStandings(userDisplayName: String, slateSize: Int) -> [ScrimmageStanding] {
        var rows: [ScrimmageStanding] = [
            ScrimmageStanding(
                id: userStandingId,
                displayName: userDisplayName,
                wins: slateSize,
                losses: 0,
                rank: 1,
                isUser: true
            ),
        ]

        let sortedBots = ScrimmageData.bots.sorted { $0.agreesWithUserCount > $1.agreesWithUserCount }
        for (offset, bot) in sortedBots.enumerated() {
            rows.append(
                ScrimmageStanding(
                    id: bot.id,
                    displayName: bot.displayName,
                    wins: bot.agreesWithUserCount,
                    losses: slateSize - bot.agreesWithUserCount,
                    rank: offset + 2,
                    isUser: false
                )
            )
        }
        return rows
    }
}
