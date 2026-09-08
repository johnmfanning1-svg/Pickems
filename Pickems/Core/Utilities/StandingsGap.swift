import Foundation

enum StandingsGap {
    /// Win difference vs `them`. Positive means you are ahead.
    static func gamesAhead(youWins: Int, themWins: Int) -> Int {
        youWins - themWins
    }

    static func gapPhrase(gamesAhead: Int) -> String {
        if gamesAhead == 0 { return "Even" }
        let magnitude = abs(gamesAhead)
        let unit = magnitude == 1 ? "game" : "games"
        let direction = gamesAhead > 0 ? "ahead" : "back"
        return "\(magnitude) \(unit) \(direction)"
    }

    /// First place (including ties) keeps batting average. Everyone else is games back of the leader.
    static func leaderboardCaption(
        rank: Int,
        wins: Int,
        losses: Int,
        leaderWins: Int?
    ) -> String {
        guard let leaderWins, rank > 1 else {
            return BattingAverage.formatted(wins: wins, losses: losses)
        }
        return gapPhrase(gamesAhead: gamesAhead(youWins: wins, themWins: leaderWins))
    }
}
