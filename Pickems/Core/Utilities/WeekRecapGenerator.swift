import Foundation

enum WeekRecapGenerator {
    static func recap(
        groupName: String,
        week: WeekSummary,
        standings: GroupStandings?,
        userId: String?
    ) -> String {
        recap(groupName: groupName, week: week, entries: standings?.entries ?? [], userId: userId)
    }

    static func recap(
        groupName: String,
        week: WeekSummary,
        entries: [StandingEntry],
        userId: String?
    ) -> String {
        let you = userId.flatMap { id in entries.first(where: { $0.id == id }) }

        guard week.status == .scored else {
            var lines = ["Week \(week.weekNumber) is still in progress."]
            if let you, you.weeklyWins + you.weeklyLosses > 0 {
                lines.append("Your week so far: \(you.weeklyWins)–\(you.weeklyLosses) against the spread")
            }
            return lines.joined(separator: "\n")
        }

        var lines: [String] = ["\(groupName) — Week \(week.weekNumber) Recap"]

        if let leader = entries.min(by: { $0.rank < $1.rank }) ?? entries.first {
            lines.append("Leader: \(leader.displayName) (\(leader.weeklyWins)–\(leader.weeklyLosses))")
        }

        if let you {
            lines.append("Your week: \(you.weeklyWins)–\(you.weeklyLosses) against the spread")
            if you.weeklyWins + you.weeklyLosses > 0 {
                lines.append("Batting average: \(String(format: "%.3f", you.weeklyBattingAverage))")
            }
        }

        let tied = entries.filter(\.isTied).count
        if tied > 0 {
            lines.append("\(tied) player(s) tied — check the leaderboard for tie-breakers.")
        }

        return lines.joined(separator: "\n")
    }
}
