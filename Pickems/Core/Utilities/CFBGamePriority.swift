import Foundation

/// Display priority for home-page "CFB This Week" matchups.
/// Order: Top 25 involvement → SEC → Group of 5 → everything else.
enum CFBGamePriority {
    enum Tier: Int, Comparable, CaseIterable {
        case ranked = 0
        case sec = 1
        case groupOf5 = 2
        case other = 3

        static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// ESPN conference group IDs.
    static let secConferenceId = "8"
    static let groupOf5ConferenceIds: Set<String> = [
        "151", // American
        "12",  // Conference USA
        "15",  // MAC
        "17",  // Mountain West
        "37"   // Sun Belt
    ]

    static func isRanked(_ rank: Int?) -> Bool {
        guard let rank else { return false }
        return (1...25).contains(rank)
    }

    static func bestRank(_ lhs: Int?, _ rhs: Int?) -> Int? {
        let ranked = [lhs, rhs].compactMap { rank -> Int? in
            isRanked(rank) ? rank : nil
        }
        return ranked.min()
    }

    static func tier(
        homeConferenceId: String?,
        awayConferenceId: String?,
        homeRank: Int?,
        awayRank: Int?
    ) -> Tier {
        if isRanked(homeRank) || isRanked(awayRank) {
            return .ranked
        }

        let conferences = Set([homeConferenceId, awayConferenceId].compactMap { $0 })
        if conferences.contains(secConferenceId) {
            return .sec
        }
        if !conferences.isDisjoint(with: groupOf5ConferenceIds) {
            return .groupOf5
        }
        return .other
    }

    /// Sort key: tier, then best Top 25 rank (ranked tier only), then earlier kickoff.
    static func areInPriorityOrder(
        lhsTier: Tier,
        lhsBestRank: Int?,
        lhsKickoff: Date,
        rhsTier: Tier,
        rhsBestRank: Int?,
        rhsKickoff: Date
    ) -> Bool {
        if lhsTier != rhsTier {
            return lhsTier < rhsTier
        }
        if lhsTier == .ranked {
            let left = lhsBestRank ?? Int.max
            let right = rhsBestRank ?? Int.max
            if left != right {
                return left < right
            }
        }
        return lhsKickoff < rhsKickoff
    }
}

extension ESPNGame {
    var priorityTier: CFBGamePriority.Tier {
        CFBGamePriority.tier(
            homeConferenceId: homeConferenceId,
            awayConferenceId: awayConferenceId,
            homeRank: homeRank,
            awayRank: awayRank
        )
    }

    var bestRank: Int? {
        CFBGamePriority.bestRank(homeRank, awayRank)
    }
}
