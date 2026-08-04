import Foundation

actor ESPNService {
    static let shared = ESPNService()

    private var scoreboardCache: [String: CachedScoreboard] = [:]
    private var weekCache: CFBWeekInfo?
    private var weekCacheTime: Date?
    private let browseCacheTTL: TimeInterval = 15 * 60
    private let liveCacheTTL: TimeInterval = 60

    private struct CachedScoreboard {
        let games: [ESPNGame]
        let fetchedAt: Date
    }

    func currentWeek(forceRefresh: Bool = false) async throws -> CFBWeekInfo {
        if !forceRefresh,
           let weekCache,
           let weekCacheTime,
           Date().timeIntervalSince(weekCacheTime) < browseCacheTTL {
            return weekCache
        }

        guard let url = Self.currentWeekURL(seasonType: 2) else {
            throw ESPNError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ESPNError.requestFailed
        }

        let decoded = try JSONDecoder().decode(ESPNScoreboardMetaResponse.self, from: data)
        let season = decoded.season?.year ?? Calendar.current.component(.year, from: Date())
        let week = decoded.week?.number ?? 1
        let info = CFBWeekInfo(
            seasonYear: season,
            weekNumber: week,
            seasonType: decoded.season?.type ?? 2,
            label: "Season \(String(season)) | Week \(week)"
        )
        weekCache = info
        weekCacheTime = Date()
        CFBWeekSync.persistLastKnownWeek(info)
        return info
    }

    func fetchScoreboard(week: Int, seasonType: Int = 2, live: Bool = false) async throws -> [ESPNGame] {
        let cacheKey = "\(seasonType)-\(week)-fbs-\(live ? "live" : "browse")"
        let ttl = live ? liveCacheTTL : browseCacheTTL

        if let cached = scoreboardCache[cacheKey], Date().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.games
        }

        guard let url = Self.scoreboardURL(week: week, seasonType: seasonType) else {
            throw ESPNError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ESPNError.requestFailed
        }

        let decoded = try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data)
        let games = (decoded.events ?? []).compactMap { parseEvent($0) }
        scoreboardCache[cacheKey] = CachedScoreboard(games: games, fetchedAt: Date())
        return games
    }

    func fetchGame(eventId: String) async throws -> ESPNGame? {
        let games = try await fetchScoreboard(week: (try? await currentWeek())?.weekNumber ?? 1, live: true)
        if let match = games.first(where: { $0.espnEventId == eventId }) {
            return match
        }

        var components = URLComponents(string: Self.scoreboardBaseURL)!
        components.queryItems = [URLQueryItem(name: "event", value: eventId)]
        guard let url = components.url else { throw ESPNError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data)
        return decoded.events?.first.flatMap { parseEvent($0) }
    }

    func liveGameCards(
        week: Int,
        slateEventIds: Set<String> = [],
        userPicks: [String: String] = [:],
        slateGames: [SlateGame] = []
    ) async throws -> [ESPNLiveGameCard] {
        let espnGames = try await fetchScoreboard(week: week, live: true)
        let slateByEventId = Dictionary(uniqueKeysWithValues: slateGames.map { ($0.espnEventId, $0) })

        return espnGames.map { game in
            let isSlate = slateEventIds.contains(game.espnEventId)
            let slateGame = slateByEventId[game.espnEventId]
            let pickedTeamId = userPicks[game.espnEventId] ?? userPicks[game.id]
            let pickAbbr: String? = {
                guard let pickedTeamId else { return nil }
                return pickedTeamId == game.homeTeamId ? game.homeTeamAbbreviation : game.awayTeamAbbreviation
            }()
            let result = pickOutcome(game: game, slateGame: slateGame, pickedTeamId: pickedTeamId)

            return ESPNLiveGameCard(
                id: game.espnEventId,
                espnEventId: game.espnEventId,
                awayTeamName: game.awayTeamName,
                awayTeamAbbreviation: game.awayTeamAbbreviation,
                awayTeamLogoURL: game.awayTeamLogoURL,
                homeTeamName: game.homeTeamName,
                homeTeamAbbreviation: game.homeTeamAbbreviation,
                homeTeamLogoURL: game.homeTeamLogoURL,
                awayScore: game.awayScore,
                homeScore: game.homeScore,
                spreadLabel: game.spreadDisplayLabel ?? slateGame.map { g in
                    g.spreadLabel(for: g.spreadTeamId)
                },
                status: game.status,
                statusDetail: statusDetail(for: game),
                kickoff: game.kickoff,
                isSlateGame: isSlate,
                userPickTeamAbbreviation: pickAbbr,
                pickResult: result
            )
        }
    }

    private func pickOutcome(game: ESPNGame, slateGame: SlateGame?, pickedTeamId: String?) -> ESPNLiveGameCard.PickResult? {
        guard pickedTeamId != nil else { return nil }
        let scoringGame = slateGame ?? game.toSlateGame()
        switch ScoringEngine.isPickCorrect(pickedTeamId: pickedTeamId!, game: scoringGame) {
        case .some(true): return .win
        case .some(false): return .loss
        case .none:
            return game.status == .final ? .push : .pending
        }
    }

    private func statusDetail(for game: ESPNGame) -> String {
        switch game.status {
        case .scheduled:
            return game.kickoff.formatted(date: .abbreviated, time: .shortened)
        case .inProgress:
            if let home = game.homeScore, let away = game.awayScore {
                return "Live · \(away)-\(home)"
            }
            return "In Progress"
        case .final:
            if let home = game.homeScore, let away = game.awayScore {
                return "Final · \(away)-\(home)"
            }
            return "Final"
        }
    }

    private func parseEvent(_ event: ESPNScoreboardResponse.ESPNEvent) -> ESPNGame? {
        guard let competition = event.competitions?.first,
              let competitors = competition.competitors,
              competitors.count == 2 else { return nil }

        guard let home = competitors.first(where: { $0.homeAway == "home" }),
              let away = competitors.first(where: { $0.homeAway == "away" }) else { return nil }

        let odds = competition.odds?.first
        let spread = parseSpread(from: odds, homeId: home.team.id, awayId: away.team.id)
        let spreadTeamId = Self.parseSpreadTeamId(
            from: odds,
            homeId: home.team.id,
            awayId: away.team.id,
            homeAbbreviation: home.team.abbreviation,
            awayAbbreviation: away.team.abbreviation
        )

        let kickoff = ISO8601DateFormatter().date(from: event.date) ?? Date()
        let status: SlateGame.GameStatus = {
            guard let type = competition.status?.type else { return .scheduled }
            if type.completed { return .final }
            if type.state == "in" { return .inProgress }
            return .scheduled
        }()

        return ESPNGame(
            id: event.id,
            espnEventId: event.id,
            competitionId: competition.id,
            homeTeamId: home.team.id,
            homeTeamName: home.team.displayName,
            homeTeamAbbreviation: home.team.abbreviation,
            homeTeamLogoURL: home.team.logo ?? home.team.logos?.first?.href,
            awayTeamId: away.team.id,
            awayTeamName: away.team.displayName,
            awayTeamAbbreviation: away.team.abbreviation,
            awayTeamLogoURL: away.team.logo ?? away.team.logos?.first?.href,
            kickoff: kickoff,
            spread: spread,
            spreadTeamId: spreadTeamId,
            status: status,
            homeScore: Int(home.score ?? ""),
            awayScore: Int(away.score ?? ""),
            homeCuratedRank: Self.normalizedCuratedRank(home.curatedRank),
            awayCuratedRank: Self.normalizedCuratedRank(away.curatedRank),
            homeConferenceId: home.team.conferenceId,
            awayConferenceId: away.team.conferenceId
        )
    }

    private func parseSpread(from odds: ESPNScoreboardResponse.ESPNOdds?, homeId: String, awayId: String) -> Double? {
        if let spread = odds?.spread { return spread }
        guard let details = odds?.details else { return nil }
        let pattern = /([A-Z]{2,4})\s*([-+]\d+\.?\d*)/
        guard let match = details.firstMatch(of: pattern) else { return nil }
        return Double(match.2)
    }

    /// Maps ESPN's unranked sentinel (99) to nil; otherwise returns the rank.
    static func normalizedCuratedRank(_ curatedRank: ESPNScoreboardResponse.ESPNCuratedRank?) -> Int? {
        guard let current = curatedRank?.current, current != 99 else { return nil }
        return current
    }

    /// Favorite from odds flags when present; otherwise derive from details (e.g. "BAMA -7.5"), then home.
    static func parseSpreadTeamId(
        from odds: ESPNScoreboardResponse.ESPNOdds?,
        homeId: String,
        awayId: String,
        homeAbbreviation: String,
        awayAbbreviation: String
    ) -> String? {
        if odds?.homeTeamOdds?.favorite == true { return homeId }
        if odds?.awayTeamOdds?.favorite == true { return awayId }

        if let details = odds?.details {
            let pattern = /([A-Z]{2,4})\s*([-+]\d+\.?\d*)/
            if let match = details.firstMatch(of: pattern) {
                let abbr = String(match.1)
                if abbr.caseInsensitiveCompare(homeAbbreviation) == .orderedSame { return homeId }
                if abbr.caseInsensitiveCompare(awayAbbreviation) == .orderedSame { return awayId }
            }
        }

        return homeId
    }

    static let scoreboardBaseURL = "https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard"

    static func currentWeekURL(seasonType: Int = 2) -> URL? {
        var components = URLComponents(string: scoreboardBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "seasontype", value: String(seasonType)),
            URLQueryItem(name: "groups", value: "80"),
            URLQueryItem(name: "limit", value: "300")
        ]
        return components.url
    }

    static func scoreboardURL(week: Int, seasonType: Int) -> URL? {
        var components = URLComponents(string: scoreboardBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "week", value: String(week)),
            URLQueryItem(name: "seasontype", value: String(seasonType)),
            URLQueryItem(name: "groups", value: "80"),
            URLQueryItem(name: "limit", value: "300")
        ]
        return components.url
    }

    enum ESPNError: LocalizedError {
        case invalidURL
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid ESPN URL."
            case .requestFailed: return "Failed to fetch games from ESPN."
            }
        }
    }
}

private struct ESPNScoreboardMetaResponse: Decodable {
    let season: ESPNSeason?
    let week: ESPNWeek?

    struct ESPNSeason: Decodable {
        let year: Int
        let type: Int
    }

    struct ESPNWeek: Decodable {
        let number: Int
    }
}
