import ActivityKit
import Foundation

/// Keep in sync with `PickemsWidget/PickemsLiveAttributes.swift`.
/// `contentVersion` 2 is the picks payload. Older activities decode as version 0
/// so the app can end them and start one that registers for push updates.
enum LiveActivitySchema {
    static let version = 2
    static let maxPicks = 3

    /// `users/{uid}.liveActivityKey`. Group ids and week ids do not contain "|".
    static func activityKey(groupId: String, weekId: String) -> String {
        "\(groupId)|\(weekId)"
    }
}

struct LiveActivityPick: Codable, Hashable {
    var gameId: String
    var picked: String
    var opponent: String
    var pickedScore: Int?
    var opponentScore: Int?
    /// `live`, `upcoming`, or `final`.
    var phase: String
    /// `pending`, `covering`, `trailing`, `won`, `lost`, or `push`.
    var result: String
    var resultLabel: String
    var kickoffUnix: Double
}

struct PickemsLiveAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var weeklyWins: Int
        var weeklyLosses: Int
        var weeklyPushes: Int
        var rank: Int?
        var rankTied: Bool
        var picks: [LiveActivityPick]
        var updatedAt: Double
        var contentVersion: Int

        var recordText: String {
            if weeklyPushes > 0 {
                return "\(weeklyWins)-\(weeklyLosses)-\(weeklyPushes)"
            }
            return "\(weeklyWins)-\(weeklyLosses)"
        }

        /// Nil at 0–0 so a join-order board cannot read as "#1".
        var rankText: String? {
            guard let rank, rank > 0, weeklyWins + weeklyLosses > 0 else { return nil }
            return rankTied ? "T-#\(rank)" : "#\(rank)"
        }

        init(
            weeklyWins: Int,
            weeklyLosses: Int,
            weeklyPushes: Int,
            rank: Int?,
            rankTied: Bool,
            picks: [LiveActivityPick],
            updatedAt: Double,
            contentVersion: Int
        ) {
            self.weeklyWins = weeklyWins
            self.weeklyLosses = weeklyLosses
            self.weeklyPushes = weeklyPushes
            self.rank = rank
            self.rankTied = rankTied
            self.picks = picks
            self.updatedAt = updatedAt
            self.contentVersion = contentVersion
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            weeklyWins = try container.decodeIfPresent(Int.self, forKey: .weeklyWins) ?? 0
            weeklyLosses = try container.decodeIfPresent(Int.self, forKey: .weeklyLosses) ?? 0
            weeklyPushes = try container.decodeIfPresent(Int.self, forKey: .weeklyPushes) ?? 0
            rank = try container.decodeIfPresent(Int.self, forKey: .rank)
            rankTied = try container.decodeIfPresent(Bool.self, forKey: .rankTied) ?? false
            picks = try container.decodeIfPresent([LiveActivityPick].self, forKey: .picks) ?? []
            if container.contains(.updatedAt), let unix = try? container.decode(Double.self, forKey: .updatedAt) {
                updatedAt = unix
            } else {
                updatedAt = 0
            }
            contentVersion = try container.decodeIfPresent(Int.self, forKey: .contentVersion) ?? 0
            // A pre-picks activity always stored a rank, including a fake #1 at 0–0.
            if !container.contains(.picks), weeklyWins + weeklyLosses == 0 {
                rank = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(weeklyWins, forKey: .weeklyWins)
            try container.encode(weeklyLosses, forKey: .weeklyLosses)
            try container.encode(weeklyPushes, forKey: .weeklyPushes)
            try container.encodeIfPresent(rank, forKey: .rank)
            try container.encode(rankTied, forKey: .rankTied)
            try container.encode(picks, forKey: .picks)
            try container.encode(updatedAt, forKey: .updatedAt)
            try container.encode(contentVersion, forKey: .contentVersion)
        }

        private enum CodingKeys: String, CodingKey {
            case weeklyWins
            case weeklyLosses
            case weeklyPushes
            case rank
            case rankTied
            case picks
            case updatedAt
            case contentVersion
        }
    }

    var groupId: String
    var groupName: String
    var weekId: String
    var weekNumber: Int
    var userDisplayName: String

    init(
        groupId: String,
        groupName: String,
        weekId: String,
        weekNumber: Int,
        userDisplayName: String
    ) {
        self.groupId = groupId
        self.groupName = groupName
        self.weekId = weekId
        self.weekNumber = weekNumber
        self.userDisplayName = userDisplayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId) ?? ""
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? ""
        weekId = try container.decodeIfPresent(String.self, forKey: .weekId) ?? ""
        weekNumber = try container.decodeIfPresent(Int.self, forKey: .weekNumber) ?? 0
        userDisplayName = try container.decodeIfPresent(String.self, forKey: .userDisplayName) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(groupName, forKey: .groupName)
        try container.encode(weekId, forKey: .weekId)
        try container.encode(weekNumber, forKey: .weekNumber)
        try container.encode(userDisplayName, forKey: .userDisplayName)
    }

    private enum CodingKeys: String, CodingKey {
        case groupId
        case groupName
        case weekId
        case weekNumber
        case userDisplayName
    }
}

/// Lock-screen tap target. Keep in sync with `LiveActivityWidgetLink` in the widget extension.
enum LiveActivityDestination {
    static func url(groupId: String, weekId: String, picks: [LiveActivityPick]) -> URL? {
        url(groupId: groupId, weekId: weekId, gameId: focusGameId(picks: picks))
    }

    static func url(groupId: String, weekId: String, gameId: String?) -> URL? {
        let group = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let week = weekId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !group.isEmpty, !week.isEmpty else { return nil }
        let focus = gameId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tail = focus.isEmpty ? "pickems" : "game/\(path(focus))"
        return URL(string: "pickems://league/\(path(group))/week/\(path(week))/\(tail)")
    }

    /// The live pick wins, even if a final is listed first. Otherwise the first row.
    static func focusGameId(picks: [LiveActivityPick]) -> String? {
        if let live = picks.first(where: { $0.phase == "live" && !$0.gameId.isEmpty }) {
            return live.gameId
        }
        return picks.first(where: { !$0.gameId.isEmpty })?.gameId
    }

    private static func path(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Which picks the lock screen shows, and whether the activity should be running.
/// Grading matches `ScoringEngine` (ATS vs Straight Up). Only the viewer's pick map is read.
enum LiveActivityContent {
    static func shouldRun(weekStatus: WeekStatus?, pickingHasLiveGame: Bool) -> Bool {
        guard let weekStatus else { return false }
        if weekStatus == .locked { return true }
        return weekStatus == .picking && pickingHasLiveGame
    }

    static func build(
        games: [SlateGame],
        picks: [String: String],
        pickMode: PickMode,
        confidenceGameId: String? = nil,
        submittedAt: Date? = nil,
        deadline: Date? = nil,
        latePenaltyWins: Int = 0,
        rank: Int? = nil,
        rankTied: Bool = false,
        rankBoardDecidedGames: Int = 0,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> PickemsLiveAttributes.ContentState {
        let scored = ScoringEngine.scorePicks(
            picks: picks,
            games: games,
            confidenceGameId: confidenceGameId,
            submittedAt: submittedAt,
            deadline: deadline,
            latePenaltyWins: latePenaltyWins,
            pickMode: pickMode
        )
        let showRank = scored.wins + scored.losses > 0
            && rankBoardDecidedGames > 0
            && (rank ?? 0) > 0
        let rows = select(candidates(games: games, picks: picks), limit: LiveActivitySchema.maxPicks)
            .map { row(for: $0, pickMode: pickMode) }
        return PickemsLiveAttributes.ContentState(
            weeklyWins: scored.wins,
            weeklyLosses: scored.losses,
            weeklyPushes: scored.pushes,
            rank: showRank ? rank : nil,
            rankTied: showRank && rankTied,
            picks: rows,
            updatedAt: updatedAt.timeIntervalSince1970,
            contentVersion: LiveActivitySchema.version
        )
    }

    private struct Candidate {
        var game: SlateGame
        var pickedTeamId: String
    }

    private static func candidates(games: [SlateGame], picks: [String: String]) -> [Candidate] {
        games.compactMap { game in
            guard let picked = trimmed(picks[game.id]) else { return nil }
            guard picked == game.homeTeamId || picked == game.awayTeamId else { return nil }
            return Candidate(game: game, pickedTeamId: picked)
        }
    }

    /// Live games, then the next picked kickoff, then the most recently kicked-off finals.
    private static func select(_ all: [Candidate], limit: Int) -> [Candidate] {
        guard limit > 0 else { return [] }
        let live = all.filter { $0.game.status == .inProgress }.sorted(by: earlierKickoff)
        let upcoming = all.filter { $0.game.status == .scheduled }.sorted(by: earlierKickoff)
        let finals = all.filter { $0.game.status == .final }.sorted(by: laterKickoff)
        var chosen: [Candidate] = []
        for item in live {
            guard chosen.count < limit else { break }
            chosen.append(item)
        }
        if chosen.count < limit, let next = upcoming.first {
            chosen.append(next)
        }
        for item in finals {
            guard chosen.count < limit else { break }
            chosen.append(item)
        }
        return chosen
    }

    private static func earlierKickoff(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.game.kickoff != rhs.game.kickoff { return lhs.game.kickoff < rhs.game.kickoff }
        return lhs.game.id < rhs.game.id
    }

    private static func laterKickoff(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.game.kickoff != rhs.game.kickoff { return lhs.game.kickoff > rhs.game.kickoff }
        return lhs.game.id < rhs.game.id
    }

    private static func row(for candidate: Candidate, pickMode: PickMode) -> LiveActivityPick {
        let game = candidate.game
        let pickedIsHome = candidate.pickedTeamId == game.homeTeamId
        let graded = grade(game: game, pickedTeamId: candidate.pickedTeamId, pickMode: pickMode)
        let ready = game.status != .scheduled && game.homeScore != nil && game.awayScore != nil
        return LiveActivityPick(
            gameId: game.id,
            picked: tag(
                pickedIsHome ? game.homeTeamAbbreviation : game.awayTeamAbbreviation,
                name: pickedIsHome ? game.homeTeamName : game.awayTeamName
            ),
            opponent: tag(
                pickedIsHome ? game.awayTeamAbbreviation : game.homeTeamAbbreviation,
                name: pickedIsHome ? game.awayTeamName : game.homeTeamName
            ),
            pickedScore: ready ? (pickedIsHome ? game.homeScore : game.awayScore) : nil,
            opponentScore: ready ? (pickedIsHome ? game.awayScore : game.homeScore) : nil,
            phase: phase(game.status),
            result: graded.result,
            resultLabel: graded.label,
            kickoffUnix: game.kickoff.timeIntervalSince1970
        )
    }

    private static func grade(
        game: SlateGame,
        pickedTeamId: String,
        pickMode: PickMode
    ) -> (result: String, label: String) {
        if game.status == .inProgress, game.homeScore == nil || game.awayScore == nil {
            return ("pending", "Live")
        }
        if let home = game.homeScore, let away = game.awayScore, game.status == .inProgress,
           game.coveredTeamId(homeScore: home, awayScore: away, pickMode: pickMode) == nil {
            return pickMode == .straightUp ? ("push", "Tied") : ("push", "Pushing")
        }
        let board = ScoringEngine.pickBoardStatus(
            pickedTeamId: pickedTeamId,
            game: game,
            pickMode: pickMode
        )
        switch board {
        case .covering: return ("covering", board.label(for: pickMode))
        case .trailing: return ("trailing", board.label(for: pickMode))
        case .won: return ("won", board.label(for: pickMode))
        case .lost: return ("lost", board.label(for: pickMode))
        case .push: return ("push", board.label(for: pickMode))
        case .pending, .none:
            return ("pending", game.status == .inProgress ? "Live" : "Pending")
        }
    }

    private static func phase(_ status: SlateGame.GameStatus) -> String {
        switch status {
        case .inProgress: return "live"
        case .final: return "final"
        case .scheduled: return "upcoming"
        }
    }

    private static func tag(_ abbreviation: String, name: String) -> String {
        let abbr = abbreviation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        if !abbr.isEmpty { return String(abbr.prefix(6)) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "TEAM" }
        return String(trimmed.prefix(4)).uppercased()
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
