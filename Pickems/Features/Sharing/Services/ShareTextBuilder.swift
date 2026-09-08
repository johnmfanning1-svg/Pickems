import Foundation

enum ShareTextBuilder {
    static func composeTweet(for result: ShareableResult) -> String {
        var lines = [result.headline, result.statsLine, result.bragLine]
        lines.append(result.promoURL)
        lines.append("\(AppConfig.cfbHashtag) \(AppConfig.appHashtag)")
        return joinedLines(lines)
    }

    static func composeMessage(for result: ShareableResult) -> String {
        joinedLines([result.headline, result.statsLine, result.bragLine])
    }

    static func weeklyHeadline(for result: WeeklyResult) -> String {
        "Week \(result.week): \(result.recordText)"
    }

    static func weeklyStatsLine(for result: WeeklyResult) -> String {
        var line = "\(result.placementText) in \(result.leagueName)"
        if let delta = result.tiebreakerDelta {
            let sign = delta >= 0 ? "+" : ""
            line += " · TB \(sign)\(delta)"
        }
        return line
    }

    static func weeklyBragLine(for result: WeeklyResult, tone: ShareTone) -> String {
        let resolvedTone = tone == .auto ? autoWeeklyTone(for: result) : tone
        switch resolvedTone {
        case .humbleBrag, .auto:
            return humbleWeeklyLine(for: result)
        case .fullDunk:
            return dunkWeeklyLine(for: result)
        }
    }

    static func seasonHeadline(for standing: SeasonStanding) -> String {
        "\(standing.season) season: #\(standing.rank)"
    }

    static func seasonStatsLine(for standing: SeasonStanding) -> String {
        var line = "\(standing.placementText) in \(standing.leagueName) · \(standing.totalPoints) wins"
        if standing.weeklyWins > 0 {
            line += " · \(standing.weeklyWins) weekly \(standing.weeklyWins == 1 ? "win" : "wins")"
        }
        if let bestWeek = standing.bestWeek, let record = standing.bestWeekRecord {
            line += " · Best: Wk \(bestWeek) (\(record.replacingOccurrences(of: "/", with: "–")))"
        }
        return line
    }

    static func seasonBragLine(for standing: SeasonStanding, tone: ShareTone) -> String {
        let resolvedTone = tone == .auto ? autoSeasonTone(for: standing) : tone
        switch resolvedTone {
        case .humbleBrag, .auto:
            return humbleSeasonLine(for: standing)
        case .fullDunk:
            return dunkSeasonLine(for: standing)
        }
    }

    private static func joinedLines(_ lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func autoWeeklyTone(for result: WeeklyResult) -> ShareTone {
        if result.isWeeklyWinner { return .fullDunk }
        if result.correctPicks > result.losses, result.rank <= 2 { return .fullDunk }
        return .humbleBrag
    }

    private static func autoSeasonTone(for standing: SeasonStanding) -> ShareTone {
        standing.isPodium ? .fullDunk : .humbleBrag
    }

    private static func humbleWeeklyLine(for result: WeeklyResult) -> String {
        if result.isWeeklyWinner {
            return "Took the week. See you on next week's slate."
        }
        if result.correctPicks > result.losses, result.rank <= 3 {
            return "Winning record. The board knows."
        }
        return "Week \(result.week) is in the books. On to the next slate."
    }

    private static func dunkWeeklyLine(for result: WeeklyResult) -> String {
        if result.isWeeklyWinner {
            return "Week \(result.week) is mine."
        }
        if result.correctPicks <= result.losses {
            return "Still in the hunt. That's the assignment."
        }
        if result.rank == 2 {
            return "One spot off the top. Not for long."
        }
        if result.rank <= 3 {
            return "Podium week. The rest of the league can catch up."
        }
        return "Still above the cut. That's the assignment."
    }

    private static func humbleSeasonLine(for standing: SeasonStanding) -> String {
        if standing.isChampion {
            return "Season champ. See you next year."
        }
        if standing.isPodium {
            return "Podium finish. Respect the grind."
        }
        return "Season wrapped. Already plotting next year's run."
    }

    private static func dunkSeasonLine(for standing: SeasonStanding) -> String {
        if standing.isChampion {
            return "Crown secured. Everyone else played for second."
        }
        if standing.rank == 2 {
            return "Runner-up. Next season's the one."
        }
        if standing.isPodium {
            return "Top 3. That's the company I keep."
        }
        return "Finished above the noise."
    }
}
