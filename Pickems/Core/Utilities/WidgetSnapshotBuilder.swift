import Foundation

/// Turns the week the app already has loaded into the optional widget snapshot fields.
enum WidgetSnapshotBuilder {
    static let maxGames = 12

    struct Extras: Equatable {
        var selectionsDeadline: Date?
        var pickemsDeadline: Date?
        var rollingLock: Bool?
        var games: [StandingsSnapshot.SnapshotGame]?
        var nextLockAt: Date?
        var picksMade: Int? = nil
        var picksTotal: Int? = nil

        static let empty = Extras(
            selectionsDeadline: nil,
            pickemsDeadline: nil,
            rollingLock: nil,
            games: nil,
            nextLockAt: nil,
            picksMade: nil,
            picksTotal: nil
        )
    }

    static func extras(
        week: WeekSummary?,
        games: [SlateGame],
        picks: [String: String],
        pickMode: PickMode,
        now: Date = Date(),
        statusTextByGameId: [String: String] = [:]
    ) -> Extras {
        guard let week else { return .empty }

        let selections: Date? = (week.status == .selection && !week.skipsSelection)
            ? week.selectionDeadline
            : nil
        let mapped = games.map {
            snapshotGame(
                $0,
                week: week,
                picks: picks,
                pickMode: pickMode,
                now: now,
                statusText: statusTextByGameId[$0.id]
            )
        }
        let counts = pickCounts(mapped)
        let next: Date? = week.isRollingLock
            ? PickDeadlineCalculator.nextLockDate(week: week, games: games, now: now)
            : nil
        return Extras(
            selectionsDeadline: selections,
            pickemsDeadline: week.pickDeadline,
            rollingLock: week.isRollingLock,
            games: cap(mapped),
            nextLockAt: next,
            picksMade: counts?.made,
            picksTotal: counts?.total
        )
    }

    /// Same league and week, rank actually moved: remember the rank we just left.
    /// An unchanged rank keeps the last movement so ▲/▼ does not vanish on the next publish.
    static func previousRank(
        currentRank: Int,
        previous: StandingsSnapshot?,
        groupId: String,
        weekNumber: Int
    ) -> Int? {
        guard currentRank > 0,
              let previous,
              previous.groupId == groupId,
              previous.weekNumber == weekNumber,
              previous.rank > 0 else { return nil }
        if previous.rank != currentRank {
            return previous.rank
        }
        return previous.previousRank
    }

    /// Full slate, not the 12-game widget cap. Locked games stay in the total.
    static func pickCounts(
        _ games: [StandingsSnapshot.SnapshotGame]
    ) -> (made: Int, total: Int)? {
        guard !games.isEmpty else { return nil }
        let made = games.filter { trimmedPick($0.userPick) != nil }.count
        return (made, games.count)
    }

    /// The week is known but its slate is not loaded. Keep the last scoreboard for this
    /// league and week. A different league or week keeps the fresh (empty) slate.
    static func carryForward(
        _ fresh: Extras,
        previous: StandingsSnapshot?,
        groupId: String,
        weekNumber: Int
    ) -> Extras {
        guard let previous, previous.groupId == groupId, previous.weekNumber == weekNumber else {
            return fresh
        }
        var carried = fresh
        carried.selectionsDeadline = previous.selectionsDeadline
        carried.pickemsDeadline = previous.pickemsDeadline
        carried.games = previous.games
        carried.nextLockAt = previous.nextLockAt
        carried.picksMade = previous.picksMade
        carried.picksTotal = previous.picksTotal
        return carried
    }

    /// Selection is not a Pickems lock. Only a game that has actually started is locked then.
    private static func isSnapshotLocked(game: SlateGame, week: WeekSummary, now: Date) -> Bool {
        if week.status == .selection {
            return WeekTransition.gameHasStarted(
                gameId: game.id,
                kickoff: game.kickoff,
                status: game.status,
                week: week,
                now: now
            )
        }
        return WeekTransition.isGameLocked(game, week: week, now: now)
    }

    private static func snapshotGame(
        _ game: SlateGame,
        week: WeekSummary,
        picks: [String: String],
        pickMode: PickMode,
        now: Date,
        statusText: String?
    ) -> StandingsSnapshot.SnapshotGame {
        let pickedId = trimmedPick(picks[game.id])
        let pickName: String?
        if pickedId == game.homeTeamId {
            pickName = game.homeTeamAbbreviation
        } else if pickedId == game.awayTeamId {
            pickName = game.awayTeamAbbreviation
        } else {
            pickName = nil
        }
        return StandingsSnapshot.SnapshotGame(
            id: game.id,
            awayShortName: game.awayTeamAbbreviation,
            homeShortName: game.homeTeamAbbreviation,
            kickoff: game.kickoff,
            isLocked: isSnapshotLocked(game: game, week: week, now: now),
            isFinal: game.status == .final,
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            userPick: pickName,
            result: result(game: game, pickedTeamId: pickedId, pickMode: pickMode),
            awayColorHex: colorHex(teamId: game.awayTeamId, abbreviation: game.awayTeamAbbreviation),
            homeColorHex: colorHex(teamId: game.homeTeamId, abbreviation: game.homeTeamAbbreviation),
            statusText: resolvedStatusText(game: game, override: statusText)
        )
    }

    private static func colorHex(teamId: String, abbreviation: String) -> String? {
        if let team = TeamThemeCatalog.team(id: teamId) {
            return team.primaryHex
        }
        return TeamThemeCatalog.teams.first {
            $0.abbreviation.caseInsensitiveCompare(abbreviation) == .orderedSame
        }?.primaryHex
    }

    private static func resolvedStatusText(game: SlateGame, override: String?) -> String? {
        if let override {
            let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        switch game.status {
        case .final:
            return "Final"
        case .inProgress:
            return "Live"
        case .scheduled:
            return game.kickoff.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
    }

    private static func result(
        game: SlateGame,
        pickedTeamId: String?,
        pickMode: PickMode
    ) -> StandingsSnapshot.SnapshotPickResult {
        switch ScoringEngine.pickBoardStatus(
            pickedTeamId: pickedTeamId,
            game: game,
            pickMode: pickMode
        ) {
        case .won: return .win
        case .lost: return .loss
        case .push: return .push
        case .none:
            return game.status == .final ? .loss : .pending
        case .pending, .covering, .trailing:
            return .pending
        }
    }

    private static func trimmedPick(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Keep live and upcoming games when a slate is longer than the widget can show.
    private static func cap(_ games: [StandingsSnapshot.SnapshotGame]) -> [StandingsSnapshot.SnapshotGame] {
        let sorted = games.sorted { $0.kickoff < $1.kickoff }
        guard sorted.count > maxGames else { return sorted }
        let active = sorted.filter { !$0.isFinal }
        if active.count >= maxGames {
            return Array(active.prefix(maxGames))
        }
        let finals = sorted.filter(\.isFinal)
        let room = maxGames - active.count
        return (active + finals.prefix(room)).sorted { $0.kickoff < $1.kickoff }
    }
}
