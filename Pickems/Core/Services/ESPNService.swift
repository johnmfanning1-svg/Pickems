import Foundation

actor ESPNService {
    static let shared = ESPNService()

    private var scoreboardCache: [String: CachedScoreboard] = [:]
    private var weekCache: CFBWeekInfo?
    private var weekCacheTime: Date?
    private var seasonWeeksCache: (year: Int, weeks: [CFBSeasonWeek], fetchedAt: Date)?
    private var browseCacheTTL: TimeInterval { ScoreboardCachePolicy.browseTTL }

    private struct CachedScoreboard {
        let games: [ESPNGame]
        let fetchedAt: Date
    }

    /// Drops in-memory scoreboard and current-week caches so the next fetch hits the network.
    func invalidateScoreboardCache() {
        scoreboardCache.removeAll()
        weekCache = nil
        weekCacheTime = nil
    }

    func currentWeek(forceRefresh: Bool = false) async throws -> CFBWeekInfo {
        if ScoreboardCachePolicy.shouldReturnCached(
            forceRefresh: forceRefresh,
            fetchedAt: weekCacheTime,
            ttl: ScoreboardCachePolicy.browseTTL
        ), let weekCache {
            return weekCache
        }

        guard let url = Self.currentWeekURL() else {
            throw ESPNError.invalidURL
        }
        let data = try await fetchData(from: url, ignoreCache: forceRefresh)

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
        cacheSeasonWeeks(year: season, from: decoded)
        return info
    }

    func seasonWeeks(year: Int) async -> [CFBSeasonWeek] {
        if let cached = seasonWeeksCache,
           cached.year == year,
           Date().timeIntervalSince(cached.fetchedAt) < browseCacheTTL {
            return cached.weeks
        }
        if weekCache == nil || weekCache?.seasonYear != year {
            _ = try? await currentWeek(forceRefresh: true)
        }
        if let cached = seasonWeeksCache, cached.year == year {
            return cached.weeks
        }
        return CFBWeekCalendar.fallbackSeasonWeeks(seasonYear: year)
    }

    private func cacheSeasonWeeks(year: Int, from decoded: ESPNScoreboardMetaResponse) {
        let regular = decoded.leagues?
            .flatMap { $0.calendar ?? [] }
            .first(where: { $0.value == "2" || ($0.label ?? "").localizedCaseInsensitiveContains("regular") })
        let espnWeeks = (regular?.entries ?? []).compactMap { entry -> ESPNCalendarWeek? in
            guard let number = Int(entry.value ?? "") else { return nil }
            return ESPNCalendarWeek(espnWeekNumber: number, detail: entry.detail ?? "Week \(number)")
        }
        let weeks = espnWeeks.isEmpty
            ? CFBWeekCalendar.fallbackSeasonWeeks(seasonYear: year)
            : CFBWeekCalendar.appSeasonWeeks(seasonYear: year, espnWeeks: espnWeeks)
        seasonWeeksCache = (year, weeks, Date())
    }

    func fetchScoreboard(
        week: Int,
        seasonType: Int = 2,
        live: Bool = false,
        forceRefresh: Bool = false
    ) async throws -> [ESPNGame] {
        let cacheKey = ScoreboardCachePolicy.key(week: week, seasonType: seasonType, live: live)
        let ttl = live ? ScoreboardCachePolicy.liveTTL : ScoreboardCachePolicy.browseTTL

        if let cached = scoreboardCache[cacheKey],
           ScoreboardCachePolicy.shouldReturnCached(
            forceRefresh: forceRefresh,
            fetchedAt: cached.fetchedAt,
            ttl: ttl
           ) {
            return cached.games
        }

        guard let url = Self.scoreboardURL(week: week, seasonType: seasonType) else {
            throw ESPNError.invalidURL
        }
        let data = try await fetchData(from: url, ignoreCache: forceRefresh)

        let decoded = try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data)
        let games = (decoded.events ?? []).compactMap { parseEvent($0) }
        scoreboardCache[cacheKey] = CachedScoreboard(games: games, fetchedAt: Date())
        return games
    }

    func fetchScoreboard(
        for week: WeekSummary,
        seasonType: Int = 2,
        live: Bool = false,
        forceRefresh: Bool = false
    ) async throws -> [ESPNGame] {
        let games = try await fetchScoreboard(
            week: week.espnScoreboardWeek,
            seasonType: seasonType,
            live: live,
            forceRefresh: forceRefresh
        )
        return games.matching(seasonYear: week.seasonYear, appWeekNumber: week.weekNumber)
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
        slateGames: [SlateGame] = [],
        forceRefresh: Bool = false
    ) async throws -> [ESPNLiveGameCard] {
        let espnGames = try await fetchScoreboard(
            week: week,
            seasonType: seasonType,
            live: true,
            forceRefresh: forceRefresh
        )
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
                awayTeamId: game.awayTeamId,
                awayTeamName: game.awayTeamName,
                awayTeamAbbreviation: game.awayTeamAbbreviation,
                awayTeamLogoURL: game.awayTeamLogoURL,
                homeTeamId: game.homeTeamId,
                homeTeamName: game.homeTeamName,
                homeTeamAbbreviation: game.homeTeamAbbreviation,
                homeTeamLogoURL: game.homeTeamLogoURL,
                awayScore: game.awayScore,
                homeScore: game.homeScore,
                spreadLabel: Self.resolvedSpreadLabel(espnGame: game, slateGame: slateGame),
                status: game.status,
                statusDetail: statusDetail(for: game),
                kickoff: game.kickoff,
                isSlateGame: isSlate,
                homeCuratedRank: game.homeCuratedRank,
                awayCuratedRank: game.awayCuratedRank,
                homeConferenceId: game.homeConferenceId,
                awayConferenceId: game.awayConferenceId,
                broadcastLabel: game.broadcastLabel,
                isNeutralSite: game.isNeutralSite,
                userPickTeamAbbreviation: pickAbbr,
                pickResult: result,
                liveSpreadLabel: Self.liveSpreadLabel(espnGame: game, isSlateGame: isSlate)
            )
        }

        let ranks = TeamRankLookup(games: espnGames)

        // Slate games missing from this ESPN week still belong on Group / My Picks.
        let presentIds = Set(cards.map(\.espnEventId))
        for slate in slateGames where !presentIds.contains(slate.espnEventId) {
            cards.append(Self.card(from: slate, userPicks: userPicks, ranks: ranks))
        }

        return cards.sorted { $0.kickoff < $1.kickoff }
    }

    func liveGameCards(
        for week: WeekSummary,
        slateEventIds: Set<String> = [],
        userPicks: [String: String] = [:],
        slateGames: [SlateGame] = [],
        forceRefresh: Bool = false
    ) async throws -> [ESPNLiveGameCard] {
        let cards = try await liveGameCards(
            week: week.espnScoreboardWeek,
            seasonType: 2,
            slateEventIds: slateEventIds,
            userPicks: userPicks,
            slateGames: slateGames,
            forceRefresh: forceRefresh
        )
        return cards.matching(seasonYear: week.seasonYear, appWeekNumber: week.weekNumber)
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

    nonisolated static func card(
        from slate: SlateGame,
        userPicks: [String: String],
        ranks: TeamRankLookup = .empty
    ) -> ESPNLiveGameCard {
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
            awayTeamId: slate.awayTeamId,
            awayTeamName: slate.awayTeamName,
            awayTeamAbbreviation: slate.awayTeamAbbreviation,
            awayTeamLogoURL: slate.awayTeamLogoURL,
            homeTeamId: slate.homeTeamId,
            homeTeamName: slate.homeTeamName,
            homeTeamAbbreviation: slate.homeTeamAbbreviation,
            homeTeamLogoURL: slate.homeTeamLogoURL,
            awayScore: slate.awayScore,
            homeScore: slate.homeScore,
            spreadLabel: slate.favoriteSpreadDisplay,
            status: slate.status,
            statusDetail: statusDetail,
            kickoff: slate.kickoff,
            isSlateGame: true,
            homeCuratedRank: ranks.rank(for: slate.homeTeamId),
            awayCuratedRank: ranks.rank(for: slate.awayTeamId),
            homeConferenceId: nil,
            awayConferenceId: nil,
            broadcastLabel: slate.broadcastLabel,
            isNeutralSite: slate.isNeutralSite,
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
            return Self.inProgressStatusDetail(
                awayScore: game.awayScore,
                homeScore: game.homeScore,
                liveClockLabel: game.liveClockLabel
            )
        case .final:
            if let home = game.homeScore, let away = game.awayScore {
                return "Final · \(away)-\(home)"
            }
            return "Final"
        }
    }

    /// ESPN's `shortDetail` is already "2nd 7:12" / "Halftime" / "OT". Fall back to period + clock.
    nonisolated static func liveClockLabel(
        shortDetail: String?,
        detail: String?,
        period: Int?,
        displayClock: String?,
        isInProgress: Bool
    ) -> String? {
        guard isInProgress else { return nil }
        if let short = cleanedStatusText(shortDetail) { return short }
        if let detail = cleanedStatusText(detail), !detail.localizedCaseInsensitiveContains("in progress") {
            return detail
        }
        let clock = cleanedStatusText(displayClock)
        if let period {
            let quarter = periodLabel(period)
            if let clock { return "\(quarter) \(clock)" }
            return quarter
        }
        return clock
    }

    nonisolated static func inProgressStatusDetail(
        awayScore: Int?,
        homeScore: Int?,
        liveClockLabel: String?
    ) -> String {
        if let homeScore, let awayScore {
            if let liveClockLabel {
                return "\(liveClockLabel) · \(awayScore)-\(homeScore)"
            }
            return "Live · \(awayScore)-\(homeScore)"
        }
        return liveClockLabel ?? "In Progress"
    }

    private nonisolated static func cleanedStatusText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func periodLabel(_ period: Int) -> String {
        switch period {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        case 4: return "4th"
        default: return "OT"
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
            awayConferenceId: away.team.conferenceId,
            broadcastLabel: Self.parseBroadcastLabel(
                broadcasts: competition.broadcasts,
                geoBroadcasts: competition.geoBroadcasts
            ),
            isNeutralSite: competition.neutralSite == true,
            liveClockLabel: Self.liveClockLabel(
                shortDetail: competition.status?.type.shortDetail,
                detail: competition.status?.type.detail,
                period: competition.status?.period,
                displayClock: competition.status?.displayClock,
                isInProgress: status == .inProgress
            )
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

    /// Favorite from odds flags when present; otherwise derive from details (e.g. "BAMA -7.5"),
    /// then ESPN's home-centric spread (positive = away favored). Never invert a named favorite.
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

        if let spread = odds?.spread, spread > 0 { return awayId }
        return homeId
    }

    /// Slate line is what Pickems scores against — Home must show the same number.
    nonisolated static func resolvedSpreadLabel(espnGame: ESPNGame, slateGame: SlateGame?) -> String? {
        if let slateGame { return slateGame.favoriteSpreadDisplay }
        return espnGame.spreadDisplayLabel
    }

    /// ESPN's current line, shown next to a locked Pickems line for reference.
    nonisolated static func liveSpreadLabel(espnGame: ESPNGame, isSlateGame: Bool) -> String? {
        guard isSlateGame else { return nil }
        return espnGame.spreadDisplayLabel
    }

    /// National `broadcasts.names[0]`, else first geo short name. Hides empty / TBD.
    static func parseBroadcastLabel(
        broadcasts: [ESPNScoreboardResponse.ESPNBroadcast]?,
        geoBroadcasts: [ESPNScoreboardResponse.ESPNGeoBroadcast]?
    ) -> String? {
        let national = broadcasts?.first(where: { ($0.market ?? "").caseInsensitiveCompare("national") == .orderedSame })
        let named = national?.names?.first ?? broadcasts?.first?.names?.first
        if let cleaned = cleanedBroadcast(named) { return cleaned }
        let geo = geoBroadcasts?.first?.media?.shortName ?? geoBroadcasts?.first?.media?.name
        return cleanedBroadcast(geo)
    }

    private static func cleanedBroadcast(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "TBD" else { return nil }
        return trimmed
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

    private func fetchData(from url: URL, ignoreCache: Bool) async throws -> Data {
        let (data, response): (Data, URLResponse)
        if ignoreCache {
            let request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            )
            (data, response) = try await URLSession.shared.data(for: request)
        } else {
            (data, response) = try await URLSession.shared.data(from: url)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ESPNError.requestFailed
        }
        return data
    }

    enum ScoreboardCachePolicy {
        static let browseTTL: TimeInterval = 15 * 60
        static let liveTTL: TimeInterval = 60

        static func key(week: Int, seasonType: Int, live: Bool) -> String {
            "\(seasonType)-\(week)-fbs-\(live ? "live" : "browse")"
        }

        static func isFresh(fetchedAt: Date, ttl: TimeInterval, now: Date = Date()) -> Bool {
            now.timeIntervalSince(fetchedAt) < ttl
        }

        /// In-memory cache is skipped when `forceRefresh` is true or the entry is missing/stale.
        static func shouldReturnCached(
            forceRefresh: Bool,
            fetchedAt: Date?,
            ttl: TimeInterval,
            now: Date = Date()
        ) -> Bool {
            guard !forceRefresh, let fetchedAt else { return false }
            return isFresh(fetchedAt: fetchedAt, ttl: ttl, now: now)
        }
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
    let leagues: [ESPNLeague]?

    struct ESPNSeason: Decodable {
        let year: Int
        let type: Int
    }

    struct ESPNWeek: Decodable {
        let number: Int
    }

    struct ESPNLeague: Decodable {
        let calendar: [ESPNCalendarBlock]?
    }

    struct ESPNCalendarBlock: Decodable {
        let label: String?
        let value: String?
        let entries: [ESPNCalendarEntry]?
    }

    struct ESPNCalendarEntry: Decodable {
        let detail: String?
        let value: String?
    }
}
