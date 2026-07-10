import Foundation

enum RivalryEngine {
    struct HeadToHead: Equatable {
        var userAId: String
        var userBId: String
        var userAWins: Int
        var userBWins: Int
        var ties: Int
        var weeksCompared: Int

        var summary: String {
            "\(userAWins)–\(userBWins)–\(ties) across \(weeksCompared) weeks"
        }
    }

    /// Compares two players week-by-week using weekly W–L from scored weeks.
    static func headToHead(
        userAId: String,
        userBId: String,
        weekResults: [(weekId: String, aWins: Int, aLosses: Int, bWins: Int, bLosses: Int)]
    ) -> HeadToHead {
        var a = 0
        var b = 0
        var ties = 0
        for week in weekResults {
            if week.aWins > week.bWins { a += 1 }
            else if week.bWins > week.aWins { b += 1 }
            else { ties += 1 }
        }
        return HeadToHead(
            userAId: userAId,
            userBId: userBId,
            userAWins: a,
            userBWins: b,
            ties: ties,
            weeksCompared: weekResults.count
        )
    }
}
