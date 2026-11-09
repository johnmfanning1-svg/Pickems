import Foundation

/// Home's league status board. Stage names follow `WeekStatus` plus in-progress games.
/// Rank copy matches `PulseRankCopy`: a 0–0 record is a dash, and a shared rank is `T-#`.
enum HomeLeagueStatus {
    enum Stage: Equatable {
        case selections
        case pickems
        case locked
        case live
        case final

        var title: String {
            switch self {
            case .selections: return "Selections"
            case .pickems: return "Pickems"
            case .locked: return "Locked"
            case .live: return "Live"
            case .final: return "Final"
            }
        }
    }

    struct Stat: Equatable {
        var recordText: String
        var rankText: String
        var accessibilityRank: String
        /// Nil until this record has a scored game, so rank motion stays off.
        var animatableRank: Int?
        /// Set when the record is a phrase, so VoiceOver does not read it as no result.
        var accessibilityRecord: String? = nil
    }

    /// Counts already on Home. The header does not load anything new.
    struct Progress: Equatable {
        var selectionsMade: Int? = nil
        var selectionsNeeded: Int? = nil
        var waitingOnSelections: Bool = false
        var picksMade: Int? = nil
        var picksNeeded: Int? = nil
        var gamesLive: Int = 0
        var gamesFinal: Int = 0
        var gamesOnSlate: Int = 0
    }

    struct Model: Equatable {
        var leagueName: String
        var weekLabel: String
        var stage: Stage?
        var detail: String?
        var week: Stat
        var season: Stat
        var accessibilityLabel: String
    }

    static func make(
        leagueName: String,
        weekNumber: Int?,
        weekStatus: WeekStatus?,
        skipsSelection: Bool = false,
        picksFullyLocked: Bool = false,
        progress: Progress = Progress(),
        weeklyPushes: Int = 0,
        weeklyEntry: StandingEntry?,
        weeklyBoard: [StandingEntry],
        seasonEntry: StandingEntry?,
        seasonBoard: [StandingEntry]
    ) -> Model {
        let stage = resolvedStage(
            status: weekStatus,
            skipsSelection: skipsSelection,
            picksFullyLocked: picksFullyLocked,
            gamesLive: progress.gamesLive
        )
        let detail = progressDetail(stage: stage, progress: progress)
        let weekLabel = weekNumber.map { "Week \($0)" } ?? "This week"
        // No week document yet: do not label another week's tallies as this week.
        let week = weekStatus == nil
            ? noStanding
            : stat(entry: weeklyEntry, board: weeklyBoard, weekly: true, pushes: weeklyPushes)
        let season = stat(entry: seasonEntry, board: seasonBoard, weekly: false)
        return Model(
            leagueName: leagueName,
            weekLabel: weekLabel,
            stage: stage,
            detail: detail,
            week: week,
            season: season,
            accessibilityLabel: accessibilityLabel(
                leagueName: leagueName,
                weekLabel: weekLabel,
                stage: stage,
                detail: detail,
                week: week,
                season: season,
                weeklyEntry: weekStatus == nil ? nil : weeklyEntry,
                seasonEntry: seasonEntry
            )
        )
    }

    private static let noResult = "\u{2014}"
    private static let allPushes = "All pushes this week"

    private static let noStanding = Stat(
        recordText: noResult,
        rankText: noResult,
        accessibilityRank: "No rank yet",
        animatableRank: nil
    )

    private static func resolvedStage(
        status: WeekStatus?,
        skipsSelection: Bool,
        picksFullyLocked: Bool,
        gamesLive: Int
    ) -> Stage? {
        guard let status else { return nil }
        if status == .scored { return .final }
        let nominating = status == .selection && !skipsSelection
        if gamesLive > 0, !nominating { return .live }
        if nominating { return .selections }
        if status == .locked || picksFullyLocked { return .locked }
        return .pickems
    }

    private static func progressDetail(stage: Stage?, progress: Progress) -> String? {
        guard let stage else { return nil }
        switch stage {
        case .selections:
            if progress.waitingOnSelections { return "Waiting on selections" }
            guard let made = progress.selectionsMade,
                  let needed = progress.selectionsNeeded,
                  needed > 0 else { return nil }
            if made >= needed { return "Selections in" }
            return "\(made) of \(needed) selections"
        case .pickems:
            guard let made = progress.picksMade,
                  let needed = progress.picksNeeded,
                  needed > 0 else { return nil }
            if made >= needed { return "Pickems in" }
            let left = needed - made
            if made == 0 {
                return needed == 1 ? "1 Pickem to make" : "\(needed) Pickems to make"
            }
            return left == 1 ? "1 Pickem left" : "\(left) Pickems left"
        case .locked:
            guard progress.gamesOnSlate > 0, progress.gamesFinal > 0 else { return nil }
            return "\(progress.gamesFinal) of \(progress.gamesOnSlate) final"
        case .live:
            guard progress.gamesLive > 0 else { return nil }
            return progress.gamesLive == 1 ? "1 game live" : "\(progress.gamesLive) games live"
        case .final:
            return nil
        }
    }

    private static func stat(
        entry: StandingEntry?,
        board: [StandingEntry],
        weekly: Bool,
        pushes: Int = 0
    ) -> Stat {
        guard let entry else { return noStanding }
        let wins = weekly ? entry.weeklyWins : entry.seasonWins
        let losses = weekly ? entry.weeklyLosses : entry.seasonLosses
        if wins + losses == 0 {
            // A push-only week has a result. Rank stays a dash: no wins means join order.
            if weekly, pushes > 0 {
                return Stat(
                    recordText: allPushes,
                    rankText: noResult,
                    accessibilityRank: "No rank yet",
                    animatableRank: nil,
                    accessibilityRecord: allPushes
                )
            }
            return Stat(
                recordText: weekly ? noResult : "0\u{2013}0",
                rankText: noResult,
                accessibilityRank: "No rank yet",
                animatableRank: nil
            )
        }
        let sharesRank = board.contains { $0.id != entry.id && $0.rank == entry.rank }
        let tied = entry.isTied || sharesRank
        let rankText = tied ? "T-#\(entry.rank)" : "#\(entry.rank)"
        let spoken = tied ? "Tied for rank \(entry.rank)" : "Rank \(entry.rank)"
        return Stat(
            recordText: "\(wins)\u{2013}\(losses)",
            rankText: rankText,
            accessibilityRank: spoken,
            animatableRank: entry.rank
        )
    }

    private static func accessibilityLabel(
        leagueName: String,
        weekLabel: String,
        stage: Stage?,
        detail: String?,
        week: Stat,
        season: Stat,
        weeklyEntry: StandingEntry?,
        seasonEntry: StandingEntry?
    ) -> String {
        var parts = [leagueName, weekLabel]
        if let stage { parts.append(stage.title) }
        if let detail { parts.append(detail) }
        parts.append(spoken("This week", stat: week, entry: weeklyEntry, weekly: true))
        parts.append(spoken("Season", stat: season, entry: seasonEntry, weekly: false))
        return parts.joined(separator: ". ")
    }

    private static func spoken(
        _ scope: String,
        stat: Stat,
        entry: StandingEntry?,
        weekly: Bool
    ) -> String {
        if let phrase = stat.accessibilityRecord {
            return "\(scope), \(phrase), \(stat.accessibilityRank)"
        }
        guard let entry, stat.recordText != noResult else {
            return "\(scope), no result yet"
        }
        let wins = weekly ? entry.weeklyWins : entry.seasonWins
        let losses = weekly ? entry.weeklyLosses : entry.seasonLosses
        return "\(scope) \(wins) to \(losses), \(stat.accessibilityRank)"
    }
}
