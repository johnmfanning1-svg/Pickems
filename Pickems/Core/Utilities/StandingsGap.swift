import Foundation

enum StandingsGap {
    /// Win difference vs `them`. Positive means you are ahead.
    static func gamesAhead(youWins: Int, themWins: Int) -> Int {
        youWins - themWins
    }

    /// Head-to-head only: `+N GA` ahead, `-N GB` back.
    static func gapPhrase(gamesAhead: Int) -> String {
        if gamesAhead == 0 { return "Even" }
        if gamesAhead > 0 { return "+\(gamesAhead) GA" }
        return "-\(abs(gamesAhead)) GB"
    }

    /// First place (including ties) keeps batting average. Everyone else is `-N GB`.
    /// A 0-0 record (wins and losses missing or zero) does not show `0.000`.
    /// First place, and any row with no leader stats, shows `Even` — the same label
    /// as every other 0-0 row tied with the leader. A 0-0 row behind a leader who
    /// already has wins stays `-N GB`.
    static func leaderboardCaption(
        rank: Int,
        wins: Int?,
        losses: Int?,
        leaderWins: Int?
    ) -> String {
        let decidedWins = wins ?? 0
        let decidedLosses = losses ?? 0
        if decidedWins + decidedLosses == 0 {
            return evenOrGamesBack(rank: rank, wins: decidedWins, leaderWins: leaderWins)
        }
        guard let leaderWins, rank > 1 else {
            return BattingAverage.formatted(wins: decidedWins, losses: decidedLosses)
        }
        return gamesBackCaption(wins: decidedWins, leaderWins: leaderWins)
    }

    /// Tied with the leader (or no leader to compare) is `Even`. Behind is `-N GB`.
    private static func evenOrGamesBack(rank: Int, wins: Int, leaderWins: Int?) -> String {
        guard let leaderWins, rank > 1 else { return "Even" }
        return gamesBackCaption(wins: wins, leaderWins: leaderWins)
    }

    private static func gamesBackCaption(wins: Int, leaderWins: Int) -> String {
        let ahead = gamesAhead(youWins: wins, themWins: leaderWins)
        if ahead >= 0 { return "Even" }
        return "-\(abs(ahead)) GB"
    }
}
