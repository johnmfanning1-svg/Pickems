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
        var selectionsMade: Int? = nil
        var selectionsTotal: Int? = nil
        var selectionQuota: String? = nil
        var selectionMembersDone: Int? = nil
        var selectionMembersTotal: Int? = nil
        var selectionGamesFilled: Int? = nil
        var selectionGamesTarget: Int? = nil

        static let empty = Extras(
            selectionsDeadline: nil,
            pickemsDeadline: nil,
            rollingLock: nil,
            games: nil,
            nextLockAt: nil,
            picksMade: nil,
            picksTotal: nil,
            selectionsMade: nil,
            selectionsTotal: nil,
            selectionQuota: nil,
            selectionMembersDone: nil,
            selectionMembersTotal: nil,
            selectionGamesFilled: nil,
            selectionGamesTarget: nil
        )
    }

    /// Scores already on screen. The widget does not fetch them itself.
    struct LiveScore: Equatable {
        var awayScore: Int?
        var homeScore: Int?
        var status: SlateGame.GameStatus
        var statusText: String?
    }

    static func extras(
        week: WeekSummary?,
        games: [SlateGame],
        picks: [String: String],
        pickMode: PickMode,
        now: Date = Date(),
        statusTextByGameId: [String: String] = [:],
        nominations: [Nomination] = [],
        userId: String = "",
        liveScores: [String: LiveScore] = [:],
        nominationsLoaded: Bool = true,
        memberQuota: Int? = nil,
        slateQuota: Int? = nil,
        memberIds: [String]? = nil,
        rulesSelectionsPerMember: Int = 0,
        slateEventIds: [String]? = nil,
        gamesTarget: Int? = nil
    ) -> Extras {
        guard let week else { return .empty }

        let scored = overlayingLiveScores(games, scores: liveScores)
        let countingSelections = week.status == .selection && !week.skipsSelection
        let userEventIds = Set(
            nominations
                .filter { $0.submittedBy == userId }
                .map(\.espnEventId)
                .filter { !$0.isEmpty }
        )
        let selections: Date? = countingSelections ? week.selectionDeadline : nil
        let markSelections = countingSelections && week.selectionMode == .member && nominationsLoaded
        let mapped = scored.map { game in
            let clock = statusTextByGameId[game.id]
                ?? statusTextByGameId[game.espnEventId]
                ?? liveScores[game.id]?.statusText
                ?? liveScores[game.espnEventId]?.statusText
            let selected: Bool? = markSelections
                ? (userEventIds.contains(game.espnEventId) || userEventIds.contains(game.id))
                : nil
            return snapshotGame(
                game,
                week: week,
                picks: picks,
                pickMode: pickMode,
                now: now,
                statusText: clock,
                isUserSelection: selected
            )
        }
        let memberCountsReady = week.selectionMode != .member || nominationsLoaded
        let counts = (countingSelections && week.selectionMode == .member && !nominationsLoaded)
            ? nil
            : pickCounts(mapped)
        let progress = memberSelectionProgress(
            week: week,
            counting: countingSelections,
            nominations: nominations,
            nominationsLoaded: nominationsLoaded,
            userId: userId,
            memberIds: memberIds,
            rulesSelectionsPerMember: rulesSelectionsPerMember,
            slateEventIds: slateEventIds,
            gamesTarget: gamesTarget
        )
        let gamesKnown = progress != nil && slateEventIds != nil && gamesTarget != nil
        let selection = selectionCounts(
            week: week,
            counting: countingSelections && memberCountsReady,
            userNominationCount: progress?.youMade ?? userEventIds.count,
            slateCount: scored.count,
            memberQuota: memberQuota,
            slateQuota: slateQuota
        )
        let next: Date? = week.isRollingLock
            ? PickDeadlineCalculator.nextLockDate(week: week, games: scored, now: now)
            : nil
        return Extras(
            selectionsDeadline: selections,
            pickemsDeadline: week.pickDeadline,
            rollingLock: week.isRollingLock,
            games: cap(mapped),
            nextLockAt: next,
            picksMade: counts?.made,
            picksTotal: counts?.total,
            selectionsMade: selection?.made,
            selectionsTotal: selection?.total,
            selectionQuota: selection?.quota,
            selectionMembersDone: progress?.membersDone,
            selectionMembersTotal: progress?.memberCount,
            selectionGamesFilled: gamesKnown ? progress?.gamesFilled : nil,
            selectionGamesTarget: gamesKnown ? progress?.gamesTarget : nil
        )
    }

    /// Prefer a live card's score when the app already has one. A final slate row stays final.
    static func overlayingLiveScores(
        _ games: [SlateGame],
        scores: [String: LiveScore]
    ) -> [SlateGame] {
        guard !scores.isEmpty else { return games }
        return games.map { game in
            guard let score = scores[game.id] ?? scores[game.espnEventId] else { return game }
            var copy = game
            if let away = score.awayScore { copy.awayScore = away }
            if let home = score.homeScore { copy.homeScore = home }
            if score.status == .final || (score.status == .inProgress && copy.status != .final) {
                copy.status = score.status
            }
            return copy
        }
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
        carried.selectionsMade = previous.selectionsMade
        carried.selectionsTotal = previous.selectionsTotal
        carried.selectionQuota = previous.selectionQuota
        carried.selectionMembersDone = previous.selectionMembersDone
        carried.selectionMembersTotal = previous.selectionMembersTotal
        carried.selectionGamesFilled = previous.selectionGamesFilled
        carried.selectionGamesTarget = previous.selectionGamesTarget
        return carried
    }

    /// Same tally as the Make Selections subtitle. Nil until member nominations and the roster are loaded.
    private static func memberSelectionProgress(
        week: WeekSummary,
        counting: Bool,
        nominations: [Nomination],
        nominationsLoaded: Bool,
        userId: String,
        memberIds: [String]?,
        rulesSelectionsPerMember: Int,
        slateEventIds: [String]?,
        gamesTarget: Int?
    ) -> MemberSelectionProgress.Counts? {
        guard counting,
              week.selectionMode == .member,
              nominationsLoaded,
              let memberIds else { return nil }
        return MemberSelectionProgress.counts(
            nominations: nominations,
            slateEventIds: slateEventIds ?? [],
            userId: userId,
            memberIds: memberIds,
            weekSelectionsPerMember: week.selectionsPerMember,
            rulesSelectionsPerMember: rulesSelectionsPerMember,
            gamesTarget: gamesTarget ?? 0
        )
    }

    /// Member quota is the signed-in user's nominations. Commissioner mode fills the slate size.
    private static func selectionCounts(
        week: WeekSummary,
        counting: Bool,
        userNominationCount: Int,
        slateCount: Int,
        memberQuota: Int?,
        slateQuota: Int?
    ) -> (made: Int, total: Int, quota: String)? {
        guard counting else { return nil }
        switch week.selectionMode {
        case .member:
            let total = memberQuota ?? week.selectionsPerMember
            return (userNominationCount, max(total, 1), WidgetSelectionQuota.member)
        case .commissioner:
            let total = slateQuota ?? week.slateSize
            return (slateCount, max(total, 1), WidgetSelectionQuota.commissioner)
        }
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
        statusText: String?,
        isUserSelection: Bool?
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
            statusText: resolvedStatusText(game: game, override: statusText),
            isUserSelection: isUserSelection
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

    /// Keep the viewer's selections and open picks, then live games, when a slate is longer than the widget can show.
    private static func cap(_ games: [StandingsSnapshot.SnapshotGame]) -> [StandingsSnapshot.SnapshotGame] {
        let sorted = games.sorted { $0.kickoff < $1.kickoff }
        guard sorted.count > maxGames else { return sorted }
        var kept: [StandingsSnapshot.SnapshotGame] = []
        var seen = Set<String>()
        func take(_ game: StandingsSnapshot.SnapshotGame) {
            guard kept.count < maxGames, seen.insert(game.id).inserted else { return }
            kept.append(game)
        }
        for game in sorted where game.isUserSelection == true {
            take(game)
        }
        for game in sorted where trimmedPick(game.userPick) != nil && !game.isFinal {
            take(game)
        }
        for game in sorted where trimmedPick(game.userPick) == nil && !game.isFinal {
            take(game)
        }
        for game in capPool(sorted.filter { !seen.contains($0.id) }, limit: maxGames - kept.count) {
            take(game)
        }
        return kept.sorted { $0.kickoff < $1.kickoff }
    }

    private static func capPool(
        _ sorted: [StandingsSnapshot.SnapshotGame],
        limit: Int
    ) -> [StandingsSnapshot.SnapshotGame] {
        guard limit > 0 else { return [] }
        guard sorted.count > limit else { return sorted }
        let active = sorted.filter { !$0.isFinal }
        if active.count >= limit {
            return Array(active.prefix(limit))
        }
        let finals = sorted.filter(\.isFinal)
        let room = limit - active.count
        return active + Array(finals.prefix(room))
    }
}
