import Foundation

enum LeagueRecapTone: String, CaseIterable, Identifiable {
    case moderate
    case edgy

    static let storageKey = "commissionerLeagueRecapTone"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .moderate: return "Moderate"
        case .edgy: return "Extremely edgy"
        }
    }
}

struct LeagueWeekRecap: Equatable {
    var headline: String
    var winnerLine: String?
    var lastPlaceLine: String?
    var highlightLine: String?
    var isFinal: Bool

    var shareText: String {
        [headline, winnerLine, lastPlaceLine, highlightLine]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var hasStory: Bool {
        winnerLine != nil || lastPlaceLine != nil || highlightLine != nil
    }
}

enum LeagueWeekRecapGenerator {
    static func recap(
        groupName: String,
        week: WeekSummary,
        entries: [StandingEntry],
        picks: [UserPick] = [],
        games: [SlateGame] = [],
        awards: WeekAwards? = nil,
        tone: LeagueRecapTone = .moderate
    ) -> LeagueWeekRecap {
        let isFinal = week.status == .scored
        let headline = isFinal
            ? "\(groupName) — Week \(week.weekNumber)"
            : "\(groupName) — Week \(week.weekNumber) (in progress)"

        let played = entries.filter { $0.weeklyWins + $0.weeklyLosses > 0 }
        guard !played.isEmpty else {
            return LeagueWeekRecap(
                headline: headline,
                winnerLine: nil,
                lastPlaceLine: nil,
                highlightLine: emptyHighlight(isFinal: isFinal, tone: tone),
                isFinal: isFinal
            )
        }

        let minRank = played.map(\.rank).min() ?? 1
        let maxRank = played.map(\.rank).max() ?? minRank
        let winners = played.filter { $0.rank == minRank }
        let cellar = played.filter { $0.rank == maxRank }

        let winnerLine = makeWinnerLine(winners: winners, isFinal: isFinal, tone: tone)
        let lastPlaceLine: String?
        if cellar.isEmpty || Set(cellar.map(\.id)) == Set(winners.map(\.id)) {
            lastPlaceLine = nil
        } else {
            lastPlaceLine = makeLastPlaceLine(cellar: cellar, isFinal: isFinal, tone: tone)
        }

        let highlight = makeHighlightLine(
            entries: played,
            winners: winners,
            cellar: cellar,
            picks: picks,
            games: games,
            awards: awards,
            tone: tone
        )

        return LeagueWeekRecap(
            headline: headline,
            winnerLine: winnerLine,
            lastPlaceLine: lastPlaceLine,
            highlightLine: highlight,
            isFinal: isFinal
        )
    }

    static func joinNames(_ names: [String]) -> String {
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        switch cleaned.count {
        case 0: return "Someone"
        case 1: return cleaned[0]
        case 2: return "\(cleaned[0]) and \(cleaned[1])"
        default:
            let lead = cleaned.dropLast().joined(separator: ", ")
            return "\(lead), and \(cleaned[cleaned.count - 1])"
        }
    }

    private static func recordText(_ entry: StandingEntry) -> String {
        "\(entry.weeklyWins)–\(entry.weeklyLosses)"
    }

    private static func emptyHighlight(isFinal: Bool, tone: LeagueRecapTone) -> String? {
        guard !isFinal else { return nil }
        switch tone {
        case .moderate: return "No scored Pickems yet."
        case .edgy: return "No scored Pickems yet. The suffering hasn't started."
        }
    }

    private static func makeWinnerLine(winners: [StandingEntry], isFinal: Bool, tone: LeagueRecapTone) -> String? {
        guard let first = winners.first else { return nil }
        let names = joinNames(winners.map(\.displayName))
        let record = recordText(first)
        switch (tone, isFinal, winners.count > 1) {
        case (.moderate, true, true):
            return "Winner (tie): \(names) at \(record)"
        case (.moderate, true, false):
            return "Winner: \(names) \(record)"
        case (.moderate, false, true):
            return "Leaders so far: \(names) at \(record)"
        case (.moderate, false, false):
            return "Leader so far: \(names) \(record)"
        case (.edgy, true, true):
            return "Split crown: \(names) at \(record). The rest of you weren't invited."
        case (.edgy, true, false):
            return "Winner: \(names) \(record). Everyone else played for second."
        case (.edgy, false, true):
            return "Running it so far: \(names) at \(record). Don't get comfortable."
        case (.edgy, false, false):
            return "Leader so far: \(names) \(record). Don't get comfortable."
        }
    }

    private static func makeLastPlaceLine(cellar: [StandingEntry], isFinal: Bool, tone: LeagueRecapTone) -> String? {
        guard let first = cellar.first else { return nil }
        let names = joinNames(cellar.map(\.displayName))
        let record = recordText(first)
        switch (tone, isFinal, cellar.count > 1) {
        case (.moderate, true, true):
            return "Last place (tie): \(names) at \(record)"
        case (.moderate, true, false):
            return "Last place: \(names) \(record)"
        case (.moderate, false, true):
            return "Last for now (tie): \(names) at \(record)"
        case (.moderate, false, false):
            return "Last for now: \(names) \(record)"
        case (.edgy, true, true):
            return "Basement (tie): \(names) at \(record). Misery loves company."
        case (.edgy, true, false):
            return "Last place: \(names) \(record). That's a week you bury."
        case (.edgy, false, true):
            return "Last for now (tie): \(names) at \(record). Plenty of time to make it worse."
        case (.edgy, false, false):
            return "Last for now: \(names) \(record). Plenty of time to make it worse."
        }
    }

    private static func makeHighlightLine(
        entries: [StandingEntry],
        winners: [StandingEntry],
        cellar: [StandingEntry],
        picks: [UserPick],
        games: [SlateGame],
        awards: WeekAwards?,
        tone: LeagueRecapTone
    ) -> String? {
        let winnerIds = Set(winners.map(\.id))
        let cellarIds = Set(cellar.map(\.id))
        let nameById = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.displayName) })

        if let perfect = entries.first(where: {
            StreakEngine.isPerfectSaturday(wins: $0.weeklyWins, losses: $0.weeklyLosses, slateSize: games.count)
        }) {
            switch tone {
            case .moderate:
                return "\(perfect.displayName) ran the table at \(recordText(perfect))."
            case .edgy:
                return "\(perfect.displayName) ran the table at \(recordText(perfect)). Unsportsmanlike. We respect it."
            }
        }

        if let chalk = chalkBustLine(picks: picks, games: games, tone: tone) {
            return chalk
        }

        if winners.count == 1,
           let winner = winners.first,
           let second = entries.filter({ !winnerIds.contains($0.id) }).min(by: { $0.rank < $1.rank }),
           winner.weeklyWins - second.weeklyWins == 1 {
            switch tone {
            case .moderate:
                return "\(winner.displayName) nipped \(second.displayName) by a game (\(recordText(winner)) vs \(recordText(second)))."
            case .edgy:
                return "\(winner.displayName) nipped \(second.displayName) by a game (\(recordText(winner)) vs \(recordText(second))). Sleep tight, \(second.displayName)."
            }
        }

        if let contraId = awards?.contrarianUserId,
           let name = nameById[contraId],
           !winnerIds.contains(contraId) {
            switch tone {
            case .moderate:
                return "\(name) was the Contrarian — unique covers nobody else had."
            case .edgy:
                return "\(name) was the Contrarian. While y'all copied each other, they cashed covers nobody else had."
            }
        }

        if let heartId = awards?.heartbreakerUserId,
           let name = nameById[heartId],
           !winnerIds.contains(heartId),
           !cellarIds.contains(heartId) {
            switch tone {
            case .moderate:
                return "\(name) was the Heartbreaker — most near-misses on the slate."
            case .edgy:
                return "\(name) was the Heartbreaker. Close only counted in the near-misses."
            }
        }

        let winningRecords = entries.filter { $0.weeklyWins > $0.weeklyLosses }.count
        if winningRecords > 0, entries.count > 1 {
            switch tone {
            case .moderate:
                return "\(winningRecords) of \(entries.count) posted a winning record."
            case .edgy:
                return "\(winningRecords) of \(entries.count) posted a winning record. The rest know who they are."
            }
        }

        return nil
    }

    private static func chalkBustLine(picks: [UserPick], games: [SlateGame], tone: LeagueRecapTone) -> String? {
        var best: (abbrev: String, coveringCount: Int, total: Int, margin: Int)?

        for game in games where game.status == .final {
            guard let home = game.homeScore, let away = game.awayScore,
                  let covered = game.coveredTeamId(homeScore: home, awayScore: away) else {
                continue
            }
            var counts: [String: Int] = [:]
            for pick in picks {
                if let team = pick.picks[game.id], !team.isEmpty {
                    counts[team, default: 0] += 1
                }
            }
            let total = counts.values.reduce(0, +)
            guard total >= 3 else { continue }
            let coveringCount = counts[covered, default: 0]
            guard let majority = counts.max(by: { $0.value < $1.value }) else { continue }
            let margin = majority.value - coveringCount
            guard majority.key != covered, margin > 0 else { continue }
            if best == nil || margin > best!.margin || (margin == best!.margin && majority.value > (total - best!.coveringCount)) {
                best = (abbrev(game, teamId: covered), coveringCount, total, margin)
            }
        }

        guard let bust = best else { return nil }
        switch tone {
        case .moderate:
            if bust.coveringCount == 0 {
                return "Nobody had \(bust.abbrev)."
            }
            return "The league faded \(bust.abbrev). Only \(bust.coveringCount) of \(bust.total) had them."
        case .edgy:
            if bust.coveringCount == 0 {
                return "Nobody had \(bust.abbrev). Collective brick."
            }
            return "The league faded \(bust.abbrev) and ate it. Only \(bust.coveringCount) of \(bust.total) had them."
        }
    }

    private static func abbrev(_ game: SlateGame, teamId: String) -> String {
        if teamId == game.homeTeamId { return game.homeTeamAbbreviation }
        if teamId == game.awayTeamId { return game.awayTeamAbbreviation }
        return "that side"
    }
}
