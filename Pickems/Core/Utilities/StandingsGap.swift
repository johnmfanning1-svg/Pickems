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
    static func leaderboardCaption(
        rank: Int,
        wins: Int,
        losses: Int,
        leaderWins: Int?
    ) -> String {
        guard let leaderWins, rank > 1 else {
            return BattingAverage.formatted(wins: wins, losses: losses)
        }
        let ahead = gamesAhead(youWins: wins, themWins: leaderWins)
        if ahead >= 0 { return "Even" }
        return "-\(abs(ahead)) GB"
    }
}
