import Foundation

enum ShareTextBuilder {
    static func composeTweet(for result: ShareableResult) -> String {
        var lines = [result.headline, result.statsLine, result.bragLine]
        lines.append(result.promoURL)
        lines.append("\(AppConfig.cfbHashtag) \(AppConfig.appHashtag)")

        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func composeMessage(for result: ShareableResult) -> String {
        var lines = [result.headline, result.statsLine, result.bragLine]
        lines.append(result.promoURL)

        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func weeklyHeadline(for result: WeeklyResult) -> String {
        "Week \(result.week) Pickems 🏈"
    }

    static func weeklyStatsLine(for result: WeeklyResult) -> String {
        var line = "\(result.placementText) in \(result.leagueName) • \(result.recordText) correct"
        if let delta = result.tiebreakerDelta {
            let sign = delta >= 0 ? "+" : ""
            line += " • TB \(sign)\(delta)"
        }
        return line
    }

    static func weeklyBragLine(for result: WeeklyResult, tone: ShareTone) -> String {
        let resolvedTone = tone == .auto ? autoWeeklyTone(for: result) : tone

        switch resolvedTone {
        case .humbleBrag:
            return humbleWeeklyLine(for: result)
        case .fullDunk:
            return dunkWeeklyLine(for: result)
        case .auto:
            return humbleWeeklyLine(for: result)
        }
    }

    static func seasonHeadline(for standing: SeasonStanding) -> String {
        "\(standing.season) \(standing.leagueName) — Final Standings"
    }

    static func seasonStatsLine(for standing: SeasonStanding) -> String {
        var line = "\(standing.rankEmoji) \(standing.placementText) • \(standing.totalPoints) pts"
        if standing.weeklyWins > 0 {
            line += " • \(standing.weeklyWins) weekly \(standing.weeklyWins == 1 ? "win" : "wins")"
        }
        if let bestWeek = standing.bestWeek, let record = standing.bestWeekRecord {
            line += " • Best: Wk \(bestWeek) (\(record))"
        }
        return line
    }

    static func seasonBragLine(for standing: SeasonStanding, tone: ShareTone) -> String {
        let resolvedTone = tone == .auto ? autoSeasonTone(for: standing) : tone

        switch resolvedTone {
        case .humbleBrag:
            return humbleSeasonLine(for: standing)
        case .fullDunk:
            return dunkSeasonLine(for: standing)
        case .auto:
            return humbleSeasonLine(for: standing)
        }
    }

    private static func autoWeeklyTone(for result: WeeklyResult) -> ShareTone {
        if result.isWeeklyWinner || result.rank <= 2 {
            return .fullDunk
        }
        if result.rank <= result.totalPlayers / 2 {
            return .humbleBrag
        }
        return .humbleBrag
    }

    private static func autoSeasonTone(for standing: SeasonStanding) -> ShareTone {
        standing.isPodium ? .fullDunk : .humbleBrag
    }

    private static func humbleWeeklyLine(for result: WeeklyResult) -> String {
        if result.isWeeklyWinner {
            return "Topped the board this week. The Fannypack is mine (for now)."
        }
        if result.rank <= 3 {
            return "Solid week on the board. The league knows who’s cooking."
        }
        return "Another week in the books. On to the next slate."
    }

    private static func dunkWeeklyLine(for result: WeeklyResult) -> String {
        if result.isWeeklyWinner {
            return "Week \(result.week) belongs to me. Tell your friends. 📣"
        }
        if result.rank == 2 {
            return "So close to #1 you can smell it. Everyone else? Not even close."
        }
        if result.rank <= 3 {
            return "Podium finish while the rest of the league is in shambles."
        }
        return "Still ahead of half this league. That’s a you problem if you’re below me."
    }

    private static func humbleSeasonLine(for standing: SeasonStanding) -> String {
        if standing.isChampion {
            return "Season champ. See you next year."
        }
        if standing.isPodium {
            return "Punched a ticket to the podium. Respect the grind."
        }
        return "Season wrapped. Already plotting next year’s run."
    }

    private static func dunkSeasonLine(for standing: SeasonStanding) -> String {
        if standing.isChampion {
            return "CROWN SECURED 👑 Everyone else fought for 2nd place."
        }
        if standing.rank == 2 {
            return "Runner-up. The only person who beat the whole league all year? Me, almost."
        }
        if standing.isPodium {
            return "Top 3 finish while the bottom half is in witness protection."
        }
        return "Finished above the noise. Tag your league and cope."
    }
}
