import Foundation

enum WeekRecapGenerator {
    static func recap(
        groupName: String,
        week: WeekSummary,
        standings: GroupStandings?,
        userId: String?
    ) -> String {
        guard week.status == .scored else {
            return "Week \(week.weekNumber) is still in progress."
        }

        var lines: [String] = ["\(groupName) — Week \(week.weekNumber) Recap"]

        if let standings, let leader = standings.entries.first {
            lines.append("Leader: \(leader.displayName) (\(leader.weeklyWins)-\(leader.weeklyLosses))")
        }

        if let userId,
           let entry = standings?.entries.first(where: { $0.id == userId }) {
            lines.append("Your week: \(entry.weeklyWins)-\(entry.weeklyLosses) against the spread")
            if entry.weeklyWins + entry.weeklyLosses > 0 {
                lines.append("Batting average: \(String(format: "%.3f", entry.weeklyBattingAverage))")
            }
        }

        if let standings {
            let tied = standings.entries.filter(\.isTied).count
            if tied > 0 {
                lines.append("\(tied) player(s) tied — check the leaderboard for tie-breakers.")
            }
        }

        return lines.joined(separator: "\n")
    }
}
