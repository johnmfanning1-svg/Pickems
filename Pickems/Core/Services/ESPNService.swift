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

        guard let url = Self.currentWeekURL() else {
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
        let weekInfo = try? await currentWeek()
        let games = try await fetchScoreboard(
            week: weekInfo?.weekNumber ?? 1,
            seasonType: weekInfo?.seasonType ?? 2,
            live: true
        )
        if let match = games.first(where: { $0.espnEventId == eventId }) {
            return match
        }

        var components = URLComponents(string: Self.scoreboardBaseURL)!
        components.queryItems = [URLQueryItem(name: "event", value: eventId)]
        guard let url = components.url else { throw ESPNError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ESPNError.requestFailed
        }
        let decoded = try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data)
        return decoded.events?.first.flatMap { parseEvent($0) }
    }

    func liveGameCards(
        week: Int,
        seasonType: Int = 2,
        slateEventIds: Set<String> = [],
        userPicks: [String: String] = [:],
        slateGames: [SlateGame] = []
    ) async throws -> [ESPNLiveGameCard] {
        let espnGames = try await fetchScoreboard(week: week, seasonType: seasonType, live: true)
        let slateByEventId = Dictionary(slateGames.map { ($0.espnEventId, $0) }, uniquingKeysWith: { _, last in last })
        let slateIds = slateEventIds.union(Set(slateGames.map(\.espnEventId)))

        var cards = espnGames.map { game in
            let slateGame = slateByEventId[game.espnEventId]
            let isSlate = slateIds.contains(game.espnEventId) || slateGame != nil
            let pickedTeamId = Self.resolvedPickedTeamId(
                espnEventId: game.espnEventId,
                espnGameId: game.id,
                slateGame: slateGame,
                userPicks: userPicks
            )
            let pickAbbr: String? = {
                guard let pickedTeamId else { return nil }
                if pickedTeamId == game.homeTeamId { return game.homeTeamAbbreviation }
                if pickedTeamId == game.awayTeamId { return game.awayTeamAbbreviation }
                if let slateGame {
                    if pickedTeamId == slateGame.homeTeamId { return slateGame.homeTeamAbbreviation }
                    if pickedTeamId == slateGame.awayTeamId { return slateGame.awayTeamAbbreviation }
                }
                return nil
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
                isTop25: game.isTop25,
                homeConferenceId: game.homeConferenceId,
                awayConferenceId: game.awayConferenceId,
                userPickTeamAbbreviation: pickAbbr,
                pickResult: result
            )
        }

        // Slate games missing from this ESPN week still belong on Group / My Picks.
        let presentIds = Set(cards.map(\.espnEventId))
        for slate in slateGames where !presentIds.contains(slate.espnEventId) {
            cards.append(Self.card(from: slate, userPicks: userPicks))
        }

        return cards.sorted { $0.kickoff < $1.kickoff }
    }

    /// Picks are stored under `SlateGame.id`, which is usually the ESPN event id but
    /// may be a Firestore document id on older weeks.
    nonisolated static func resolvedPickedTeamId(
        espnEventId: String,
        espnGameId: String,
        slateGame: SlateGame?,
        userPicks: [String: String]
    ) -> String? {
        if let team = userPicks[espnEventId], !team.isEmpty { return team }
        if espnGameId != espnEventId, let team = userPicks[espnGameId], !team.isEmpty { return team }
        if let slateId = slateGame?.id, let team = userPicks[slateId], !team.isEmpty { return team }
        return nil
    }

    nonisolated static func card(from slate: SlateGame, userPicks: [String: String]) -> ESPNLiveGameCard {
        let pickedTeamId = resolvedPickedTeamId(
            espnEventId: slate.espnEventId,
            espnGameId: slate.id,
            slateGame: slate,
            userPicks: userPicks
        )
        let pickAbbr: String? = {
            guard let pickedTeamId else { return nil }
            if pickedTeamId == slate.homeTeamId { return slate.homeTeamAbbreviation }
            if pickedTeamId == slate.awayTeamId { return slate.awayTeamAbbreviation }
            return nil
        }()
        let statusDetail: String = {
            switch slate.status {
            case .scheduled:
                return slate.kickoff.formatted(date: .abbreviated, time: .shortened)
            case .inProgress:
                if let home = slate.homeScore, let away = slate.awayScore {
                    return "Live · \(away)-\(home)"
                }
                return "In Progress"
            case .final:
                if let home = slate.homeScore, let away = slate.awayScore {
                    return "Final · \(away)-\(home)"
                }
                return "Final"
            }
        }()
        let pickResult: ESPNLiveGameCard.PickResult? = {
            guard pickedTeamId != nil else { return nil }
            switch ScoringEngine.isPickCorrect(pickedTeamId: pickedTeamId!, game: slate) {
            case .some(true): return .win
            case .some(false): return .loss
            case .none: return slate.status == .final ? .push : .pending
            }
        }()
        return ESPNLiveGameCard(
            id: slate.espnEventId,
            espnEventId: slate.espnEventId,
            awayTeamName: slate.awayTeamName,
            awayTeamAbbreviation: slate.awayTeamAbbreviation,
            awayTeamLogoURL: slate.awayTeamLogoURL,
            homeTeamName: slate.homeTeamName,
            homeTeamAbbreviation: slate.homeTeamAbbreviation,
            homeTeamLogoURL: slate.homeTeamLogoURL,
            awayScore: slate.awayScore,
            homeScore: slate.homeScore,
            spreadLabel: {
                let abbr = slate.spreadTeamId == slate.homeTeamId
                    ? slate.homeTeamAbbreviation
                    : slate.awayTeamAbbreviation
                return "\(abbr) \(slate.spreadLabel(for: slate.spreadTeamId))"
            }(),
            status: slate.status,
            statusDetail: statusDetail,
            kickoff: slate.kickoff,
            isSlateGame: true,
            isTop25: false,
            homeConferenceId: nil,
            awayConferenceId: nil,
            userPickTeamAbbreviation: pickAbbr,
            pickResult: pickResult
        )
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

        // ESPN often sends fractional seconds (`…T19:30:00.000Z`). Default ISO8601
        // parsing fails on those and previously fell back to `Date()` ("now"), which
        // stamped `pickDeadline` in the past while game rows still showed future kickoffs.
        guard let kickoff = Self.parseKickoffDate(event.date) else { return nil }
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

    static func currentWeekURL() -> URL? {
        var components = URLComponents(string: scoreboardBaseURL)!
        components.queryItems = [
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

    /// Parses ESPN ISO8601 kickoff strings with fractional seconds, full seconds,
    /// or minute precision (`2026-08-29T16:00Z` — common on scoreboard payloads).
    /// Returns nil instead of inventing "now" — callers must skip unparseable events.
    nonisolated static func parseKickoffDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) { return date }

        // ESPN often omits seconds (`…T16:00Z`). Normalize to full ISO8601.
        if let normalized = normalizeMinutePrecisionISO8601(raw) {
            if let date = fractional.date(from: normalized) { return date }
            if let date = plain.date(from: normalized) { return date }
        }
        return nil
    }

    /// Turns `2026-08-29T16:00Z` / `2026-08-29T16:00+00:00` into a seconds-bearing form.
    nonisolated static func normalizeMinutePrecisionISO8601(_ raw: String) -> String? {
        // Match …THH:mm immediately before a timezone designator (Z or ±HH:MM).
        guard let regex = try? NSRegularExpression(
            pattern: #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})(Z|[+-]\d{2}:?\d{2})$"#
        ) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              match.numberOfRanges == 3,
              let head = Range(match.range(at: 1), in: raw),
              let zone = Range(match.range(at: 2), in: raw) else { return nil }
        return "\(raw[head]):00\(raw[zone])"
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
