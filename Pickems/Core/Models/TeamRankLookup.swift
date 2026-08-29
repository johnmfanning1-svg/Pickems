import Foundation

/// Week-scoped map of ESPN team id → curated Top 25 rank (1...25).
/// Built from the scoreboard; not persisted to Firestore.
struct TeamRankLookup: Equatable, Sendable {
    private let ranksByTeamId: [String: Int]

    static let empty = TeamRankLookup(ranksByTeamId: [:])

    init(ranksByTeamId: [String: Int] = [:]) {
        self.ranksByTeamId = ranksByTeamId
    }

    init(games: [ESPNGame]) {
        var map: [String: Int] = [:]
        for game in games {
            if let rank = game.homeCuratedRank {
                map[game.homeTeamId] = rank
            }
            if let rank = game.awayCuratedRank {
                map[game.awayTeamId] = rank
            }
        }
        self.ranksByTeamId = map
    }

    init(cards: [ESPNLiveGameCard]) {
        var map: [String: Int] = [:]
        for card in cards {
            if let id = card.homeTeamId, let rank = card.homeCuratedRank {
                map[id] = rank
            }
            if let id = card.awayTeamId, let rank = card.awayCuratedRank {
                map[id] = rank
            }
        }
        self.ranksByTeamId = map
    }

    /// Prefer the better (lower) rank if the same team appears twice.
    func merging(_ other: TeamRankLookup) -> TeamRankLookup {
        var merged = ranksByTeamId
        for (teamId, rank) in other.ranksByTeamId {
            if let existing = merged[teamId] {
                merged[teamId] = min(existing, rank)
            } else {
                merged[teamId] = rank
            }
        }
        return TeamRankLookup(ranksByTeamId: merged)
    }

    func rank(for teamId: String) -> Int? {
        ranksByTeamId[teamId]
    }

    var isEmpty: Bool { ranksByTeamId.isEmpty }
}

enum TeamDisplay {
    /// ESPN curated poll rank shown on logos and labels. `nil` when unranked.
    static func top25Rank(_ rank: Int?) -> Int? {
        guard let rank, (1...25).contains(rank) else { return nil }
        return rank
    }

    /// ESPN scores-list rank beside a logo (`14`). No `#`; `nil` when unranked.
    static func logoRankText(_ rank: Int?) -> String? {
        top25Rank(rank).map(String.init)
    }

    /// Ranked abbreviation for text-only surfaces (`#5 ALA`). Unranked stays plain.
    static func rankedLabel(abbreviation: String, rank: Int?) -> String {
        guard let rank = top25Rank(rank) else { return abbreviation }
        return "#\(rank) \(abbreviation)"
    }

    enum FavoredSide: Equatable {
        case away
        case home
    }

    /// Matchup line with ranks only on ranked sides.
    /// When `favoredSide` is set, that team's abbreviation gets a trailing `*`.
    static func matchupLabel(
        awayAbbreviation: String,
        awayRank: Int?,
        homeAbbreviation: String,
        homeRank: Int?,
        separator: String = "@",
        favoredSide: FavoredSide? = nil
    ) -> String {
        let away = marked(
            rankedLabel(abbreviation: awayAbbreviation, rank: awayRank),
            favored: favoredSide == .away
        )
        let home = marked(
            rankedLabel(abbreviation: homeAbbreviation, rank: homeRank),
            favored: favoredSide == .home
        )
        return "\(away) \(separator) \(home)"
    }

    private static func marked(_ label: String, favored: Bool) -> String {
        favored ? "\(label)*" : label
    }
}
