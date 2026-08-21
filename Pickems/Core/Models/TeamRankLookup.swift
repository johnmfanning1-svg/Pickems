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
    /// Ranked abbreviation for text-only surfaces (`#5 ALA`). Unranked stays plain.
    static func rankedLabel(abbreviation: String, rank: Int?) -> String {
        guard let rank, (1...25).contains(rank) else { return abbreviation }
        return "#\(rank) \(abbreviation)"
    }

    /// Matchup line with ranks only on ranked sides.
    static func matchupLabel(
        awayAbbreviation: String,
        awayRank: Int?,
        homeAbbreviation: String,
        homeRank: Int?,
        separator: String = "@"
    ) -> String {
        let away = rankedLabel(abbreviation: awayAbbreviation, rank: awayRank)
        let home = rankedLabel(abbreviation: homeAbbreviation, rank: homeRank)
        return "\(away) \(separator) \(home)"
    }
}
