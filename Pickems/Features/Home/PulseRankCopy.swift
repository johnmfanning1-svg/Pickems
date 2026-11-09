import Foundation

/// Home pulse rank. A 0–0 week hides the number so a join-order or all-zero board cannot read as "#1".
enum PulseRankCopy {
    struct Display: Equatable {
        var rankText: String
        var detailText: String
        var accessibilityRank: String
        /// Nil until the user has a scored game, so rank motion stays off.
        var animatableRank: Int?
    }

    /// Pushes on a 0–0 record. A win or a loss returns 0 so a stale scoreless
    /// standing is not labeled push-only.
    static func scorelessPushes(
        picks: [String: String],
        games: [SlateGame],
        confidenceGameId: String? = nil,
        pickMode: PickMode = .ats
    ) -> Int {
        let scored = ScoringEngine.scorePicks(
            picks: picks,
            games: games,
            confidenceGameId: confidenceGameId,
            pickMode: pickMode
        )
        guard scored.wins == 0, scored.losses == 0 else { return 0 }
        return scored.pushes
    }

    static func display(entry: StandingEntry, board: [StandingEntry], pushes: Int = 0) -> Display {
        if entry.weeklyWins + entry.weeklyLosses == 0 {
            if pushes > 0 {
                return Display(
                    rankText: "—",
                    detailText: "All pushes this week",
                    accessibilityRank: "No rank yet",
                    animatableRank: nil
                )
            }
            return Display(
                rankText: "—",
                detailText: "No games final yet",
                accessibilityRank: "No rank yet",
                animatableRank: nil
            )
        }
        let sharesRank = board.contains { $0.id != entry.id && $0.rank == entry.rank }
        let tied = entry.isTied || sharesRank
        let rankText = tied ? "T-#\(entry.rank)" : "#\(entry.rank)"
        let spoken = tied ? "Tied for rank \(entry.rank)" : "Rank \(entry.rank)"
        return Display(
            rankText: rankText,
            detailText: "\(entry.weeklyWins)–\(entry.weeklyLosses) this week",
            accessibilityRank: spoken,
            animatableRank: entry.rank
        )
    }
}
