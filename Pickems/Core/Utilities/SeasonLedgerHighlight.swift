import Foundation

enum SeasonLedgerWinHighlight: Equatable, Sendable {
    case none
    case best
    case tie
}

enum SeasonLedgerHighlight {
  /// Weekly win totals per member id → highlight for the Wins cell only.
    static func winHighlights(weeklyWinsByMemberId: [String: Int]) -> [String: SeasonLedgerWinHighlight] {
        guard !weeklyWinsByMemberId.isEmpty else { return [:] }
        let values = Array(weeklyWinsByMemberId.values)
        guard let maxWins = values.max() else {
            return Dictionary(uniqueKeysWithValues: weeklyWinsByMemberId.keys.map { ($0, .none) })
        }
        let atMax = values.filter { $0 == maxWins }.count
        if atMax == values.count {
            return Dictionary(uniqueKeysWithValues: weeklyWinsByMemberId.keys.map { ($0, .none) })
        }
        if atMax == 1 {
            return Dictionary(uniqueKeysWithValues: weeklyWinsByMemberId.map {
                ($0.key, $0.value == maxWins ? .best : .none)
            })
        }
        return Dictionary(uniqueKeysWithValues: weeklyWinsByMemberId.map {
            ($0.key, $0.value == maxWins ? .tie : .none)
        })
    }
}

enum SeasonLedgerGamesBack {
    /// Games behind the season win leader(s). Tied leaders show an em dash.
    static func caption(memberWins: Int, leaderWins: Int) -> String {
        let gap = leaderWins - memberWins
        if gap == 0 { return "—" }
        return "−\(gap)"
    }

    static func leaderWins(memberSeasonWins: [String: Int]) -> Int {
        memberSeasonWins.values.max() ?? 0
    }
}

enum SeasonLedgerWeekTitle {
    static func rowTitle(for week: WeekSummary) -> String {
        let lowered = week.id.lowercased()
        if lowered.contains("army") && lowered.contains("navy") {
            return "Army Navy"
        }
        if lowered.contains("bowl") {
            return "Bowls"
        }
        return "Week \(week.weekNumber)"
    }
}