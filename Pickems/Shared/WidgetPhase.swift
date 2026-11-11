import Foundation

/// Keep the app copy (`Pickems/Shared`) and the widget copy (`PickemsWidget`) identical.
enum WidgetDeadlineKind: Equatable {
    case selections
    case pickems

    var label: String {
        switch self {
        case .selections: return "Selections"
        case .pickems: return "Pick Deadline"
        }
    }
}

/// Which home-screen layout the current snapshot should use.
enum WidgetPhase: Equatable {
    case preseason
    case deadline(Date, WidgetDeadlineKind)
    case scoreboard
    case standings
    case empty

    /// Pure phase choice. Missing slate data falls back to standings, which is today's widget.
    static func resolve(snapshot: StandingsSnapshot?, now: Date) -> WidgetPhase {
        guard let snapshot else { return .empty }
        if let kickoff = snapshot.seasonKickoffAt, now < kickoff {
            return .preseason
        }

        let games = snapshot.games ?? []
        if !games.isEmpty {
            if games.allSatisfy(\.isFinal) {
                return .standings
            }
            if games.contains(where: { hasStarted($0, now: now) }) {
                return .scoreboard
            }
        }

        if let next = nextOpenDeadline(snapshot: snapshot, now: now) {
            return .deadline(next.date, next.kind)
        }
        return .standings
    }

    /// Soonest kickoff that is still open. Used for the rolling-lock line, including future timeline entries.
    static func nextLockDate(snapshot: StandingsSnapshot, now: Date) -> Date? {
        guard snapshot.rollingLock == true else { return nil }
        if let games = snapshot.games, !games.isEmpty {
            return games
                .filter { !$0.isFinal && !$0.isLocked && $0.kickoff > now }
                .map(\.kickoff)
                .min()
        }
        if let stored = snapshot.nextLockAt, stored > now {
            return stored
        }
        return nil
    }

    /// Instants after `now` when the phase or the next-lock line can change without a new snapshot.
    static func boundaryDates(snapshot: StandingsSnapshot, now: Date) -> [Date] {
        var dates: [Date] = []
        if let kickoff = snapshot.seasonKickoffAt, kickoff > now {
            dates.append(kickoff)
        }
        if let date = snapshot.selectionsDeadline, date > now {
            dates.append(date)
        }
        if let date = snapshot.pickemsDeadline, date > now {
            dates.append(date)
        }
        for game in snapshot.games ?? [] where !game.isFinal && game.kickoff > now {
            dates.append(game.kickoff)
        }
        return uniqueSorted(dates)
    }

    /// Timeline entry dates, including `now`, so a boundary flips the phase while the entry is current.
    static func entryDates(snapshot: StandingsSnapshot, now: Date) -> [Date] {
        uniqueSorted([now] + boundaryDates(snapshot: snapshot, now: now))
    }

    /// One entry at every known transition (selection deadline, picks lock, each kickoff)
    /// so the phase flips while that entry is current, even if a reload is delayed.
    /// Scoreboard uses the same dates so the next-lock line can move with kickoffs.
    static func timelineDates(snapshot: StandingsSnapshot?, phase: WidgetPhase, now: Date) -> [Date] {
        guard let snapshot else { return [now] }
        switch phase {
        case .deadline, .standings, .scoreboard:
            return entryDates(snapshot: snapshot, now: now)
        case .preseason, .empty:
            return [now]
        }
    }

    /// Scoreboard data older than 30 minutes is stale. Every other phase uses a day.
    /// A missing snapshot, or an `updatedAt` in the future, is not stale.
    static func isStale(snapshot: StandingsSnapshot?, now: Date) -> Bool {
        guard let snapshot else { return false }
        let age = now.timeIntervalSince(snapshot.updatedAt)
        guard age >= 0 else { return false }
        switch resolve(snapshot: snapshot, now: now) {
        case .scoreboard:
            return age > 30 * 60
        case .empty:
            return false
        case .preseason, .deadline, .standings:
            return age > 24 * 60 * 60
        }
    }

    /// Preseason keeps at most two entries (now, and the next day boundary or kickoff).
    /// The reload date is never later than kickoff.
    static func preseasonTimeline(
        kickoff: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> (dates: [Date], reload: Date) {
        let start = calendar.startOfDay(for: now)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: start)
            ?? now.addingTimeInterval(24 * 60 * 60)
        let reload = min(kickoff, nextMidnight)
        var dates = [now]
        if reload > now {
            dates.append(reload)
        }
        return (Array(dates.prefix(2)), reload)
    }

    /// When to ask WidgetKit for a new timeline. Scoreboard polls for scores.
    /// Deadline and standings wait until the entry that flips the phase.
    static func reloadDate(phase: WidgetPhase, dates: [Date], now: Date) -> Date {
        let scoreboardRefresh = now.addingTimeInterval(15 * 60)
        switch phase {
        case .deadline, .standings:
            return dates.first(where: { $0 > now }) ?? scoreboardRefresh
        case .scoreboard, .preseason, .empty:
            return scoreboardRefresh
        }
    }

    private static func hasStarted(_ game: StandingsSnapshot.SnapshotGame, now: Date) -> Bool {
        game.isFinal || game.isLocked || game.kickoff <= now
    }

    private static func nextOpenDeadline(
        snapshot: StandingsSnapshot,
        now: Date
    ) -> (date: Date, kind: WidgetDeadlineKind)? {
        var candidates: [(date: Date, kind: WidgetDeadlineKind)] = []
        if let selections = snapshot.selectionsDeadline, selections > now {
            candidates.append((selections, .selections))
        }
        if let pickems = snapshot.pickemsDeadline, pickems > now {
            candidates.append((pickems, .pickems))
        }
        return candidates.min { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.kind == .selections && rhs.kind == .pickems
            }
            return lhs.date < rhs.date
        }
    }

    private static func uniqueSorted(_ dates: [Date]) -> [Date] {
        var seen = Set<Date>()
        return dates.filter { seen.insert($0).inserted }.sorted()
    }
}

enum WidgetDeepLink {
    /// Existing app routes. Selections has no week path; Pickems, the scoreboard, and standings do.
    static func url(phase: WidgetPhase, snapshot: StandingsSnapshot?) -> URL? {
        guard let snapshot, !snapshot.groupId.isEmpty else { return nil }
        let weekId = "\(snapshot.seasonYear)-W\(snapshot.weekNumber)"
        switch phase {
        case .deadline(_, .selections):
            return selectionsURL(groupId: snapshot.groupId)
        case .deadline(_, .pickems), .scoreboard:
            return leagueURL(groupId: snapshot.groupId, weekId: weekId, tail: "pickems")
        case .standings:
            return leagueURL(groupId: snapshot.groupId, weekId: weekId, tail: "leaderboard")
        case .preseason, .empty:
            return nil
        }
    }

    private static func selectionsURL(groupId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "pickems"
        components.host = "selections"
        components.queryItems = [URLQueryItem(name: "group", value: groupId)]
        return components.url
    }

    static func gameURL(snapshot: StandingsSnapshot, gameId: String) -> URL? {
        guard !snapshot.groupId.isEmpty, !gameId.isEmpty else { return nil }
        let weekId = "\(snapshot.seasonYear)-W\(snapshot.weekNumber)"
        return leagueURL(groupId: snapshot.groupId, weekId: weekId, tail: "game/\(gameId)")
    }

    static func leaderboardURL(snapshot: StandingsSnapshot) -> URL? {
        url(phase: .standings, snapshot: snapshot)
    }

    private static func leagueURL(groupId: String, weekId: String, tail: String) -> URL? {
        var components = URLComponents()
        components.scheme = "pickems"
        components.host = "league"
        components.path = "/\(groupId)/week/\(weekId)/\(tail)"
        return components.url
    }
}

enum WidgetPickStatus: Equatable {
    case winning
    case losing
    case tied
    case noPick
    case finalWin
    case finalLoss
    case push
    case upcoming

    /// Glyph plus the spoken name. Color is applied by the view, never alone.
    var glyph: String? {
        switch self {
        case .winning: return "▲"
        case .losing: return "▼"
        case .finalWin: return "✓"
        case .finalLoss: return "✗"
        case .tied, .push: return "–"
        case .noPick, .upcoming: return nil
        }
    }

    var spokenName: String {
        switch self {
        case .winning: return "winning"
        case .losing: return "losing"
        case .tied: return "tied"
        case .noPick: return "no pick"
        case .finalWin: return "win"
        case .finalLoss: return "loss"
        case .push: return "push"
        case .upcoming: return "upcoming"
        }
    }
}

enum WidgetScoreboard {
    static func pickStatus(_ game: StandingsSnapshot.SnapshotGame, now: Date) -> WidgetPickStatus {
        let pick = game.userPick?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPick = !(pick ?? "").isEmpty
        if game.isFinal {
            guard hasPick else { return .noPick }
            switch game.result {
            case .win: return .finalWin
            case .loss: return .finalLoss
            case .push: return .push
            case .pending:
                return compared(game, pick: pick ?? "") ?? .push
            }
        }
        let started = game.isLocked || game.kickoff <= now || game.awayScore != nil || game.homeScore != nil
        guard started else { return hasPick ? .upcoming : .noPick }
        guard hasPick else { return .noPick }
        return compared(game, pick: pick ?? "") ?? .tied
    }

    /// Live games first, then the user's losing picks, then everything else. Truncates to `limit`.
    static func ordered(
        _ games: [StandingsSnapshot.SnapshotGame],
        now: Date,
        limit: Int
    ) -> [StandingsSnapshot.SnapshotGame] {
        guard limit > 0 else { return [] }
        let ranked = games.sorted { lhs, rhs in
            let left = priority(lhs, now: now)
            let right = priority(rhs, now: now)
            if left != right { return left < right }
            return lhs.kickoff < rhs.kickoff
        }
        return Array(ranked.prefix(limit))
    }

    private static func priority(_ game: StandingsSnapshot.SnapshotGame, now: Date) -> Int {
        let live = !game.isFinal && (game.isLocked || game.kickoff <= now || game.awayScore != nil || game.homeScore != nil)
        if live { return 0 }
        if pickStatus(game, now: now) == .finalLoss { return 1 }
        return 2
    }

    private static func compared(_ game: StandingsSnapshot.SnapshotGame, pick: String) -> WidgetPickStatus? {
        guard let away = game.awayScore, let home = game.homeScore else { return nil }
        let pickedAway = pick == game.awayShortName
        let pickedHome = pick == game.homeShortName
        guard pickedAway || pickedHome else { return nil }
        let pickedScore = pickedAway ? away : home
        let other = pickedAway ? home : away
        if pickedScore > other { return .winning }
        if pickedScore < other { return .losing }
        return .tied
    }
}

enum WidgetInlineCopy {
    static func text(phase: WidgetPhase, snapshot: StandingsSnapshot?, now: Date) -> String {
        switch phase {
        case .deadline(let date, let kind):
            let label = kind == .selections ? "Selections lock" : "Picks lock"
            return "\(label) \(compactRemaining(date.timeIntervalSince(now)))"
        case .scoreboard:
            guard let snapshot else { return "Live" }
            return "Live: \(snapshot.weeklyWins)-\(snapshot.weeklyLosses) this week"
        case .standings:
            guard let snapshot else { return "Standings" }
            if snapshot.rank > 0, snapshot.totalPlayers > 0 {
                return "#\(snapshot.rank) of \(snapshot.totalPlayers) · \(snapshot.weeklyRecord)"
            }
            return snapshot.weeklyRecord
        case .preseason:
            guard let kickoff = snapshot?.seasonKickoffAt else { return "Kickoff" }
            return "Kickoff \(compactRemaining(kickoff.timeIntervalSince(now)))"
        case .empty:
            return "Open Pickems"
        }
    }

    static func compactRemaining(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 {
            let leftover = hours % 24
            return leftover > 0 ? "\(days)d \(leftover)h" : "\(days)d"
        }
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        }
        return "\(max(minutes, 0))m"
    }
}

enum WidgetStandingsCopy {
    /// ▲ when the user climbed, ▼ when they fell. Nil when rank is unchanged or unknown.
    static func deltaSymbol(rank: Int, previousRank: Int?) -> String? {
        guard rank > 0, let previousRank, previousRank > 0, previousRank != rank else { return nil }
        let delta = previousRank - rank
        if delta > 0 { return "▲\(delta)" }
        return "▼\(-delta)"
    }

    /// Wins behind the leader. Falls back to ranks behind when the leader is not in the payload.
    static func backOfFirst(_ snapshot: StandingsSnapshot) -> String? {
        guard snapshot.rank > 1 else { return nil }
        if let leader = snapshot.topEntries.first(where: { $0.rank == 1 })
            ?? snapshot.topEntries.min(by: { $0.rank < $1.rank }) {
            let gap = leader.weeklyWins - snapshot.weeklyWins
            if gap > 0 { return "\(gap) back of 1st" }
            return nil
        }
        let ranksBack = snapshot.rank - 1
        guard ranksBack > 0 else { return nil }
        return "\(ranksBack) back of 1st"
    }
}

enum WidgetPicksOwed: Equatable {
    /// Nil when the snapshot predates pick counts, so the deadline layout stays round one.
    static func owed(made: Int?, total: Int?) -> (made: Int, total: Int, left: Int)? {
        guard let made, let total, total > 0 else { return nil }
        let left = max(0, total - made)
        return (made, total, left)
    }
}

enum WidgetSelectionQuota {
    static let member = "member"
    static let commissioner = "commissioner"
}

/// The Make Selections subtitle. Missing counts drop out instead of rendering a blank fraction.
enum WidgetSelectionProgressLine {
    static func subtitle(
        youMade: Int,
        youTotal: Int,
        membersDone: Int,
        membersTotal: Int,
        gamesFilled: Int,
        gamesTarget: Int
    ) -> String {
        parts(
            you: (youMade, youTotal),
            members: (membersDone, membersTotal),
            games: (gamesFilled, gamesTarget),
            compact: false
        ).joined(separator: " · ")
    }

    /// Nil when every part is missing. `compact` is the narrow-family variant of the same counts.
    static func line(
        youMade: Int?,
        youTotal: Int?,
        membersDone: Int?,
        membersTotal: Int?,
        gamesFilled: Int?,
        gamesTarget: Int?,
        compact: Bool = false
    ) -> String? {
        let pieces = parts(
            you: pair(youMade, youTotal),
            members: pair(membersDone, membersTotal),
            games: pair(gamesFilled, gamesTarget),
            compact: compact
        )
        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " · ")
    }

    static func line(snapshot: StandingsSnapshot, compact: Bool = false) -> String? {
        line(
            youMade: snapshot.selectionsMade,
            youTotal: snapshot.selectionsTotal,
            membersDone: snapshot.selectionMembersDone,
            membersTotal: snapshot.selectionMembersTotal,
            gamesFilled: snapshot.selectionGamesFilled,
            gamesTarget: snapshot.selectionGamesTarget,
            compact: compact
        )
    }

    private static func pair(_ made: Int?, _ total: Int?) -> (Int, Int)? {
        guard let made, let total else { return nil }
        return (made, total)
    }

    private static func parts(
        you: (Int, Int)?,
        members: (Int, Int)?,
        games: (Int, Int)?,
        compact: Bool
    ) -> [String] {
        var pieces: [String] = []
        if let you {
            pieces.append(compact ? "You \(you.0)/\(you.1)" : "You: \(you.0)/\(you.1)")
        }
        if let members {
            pieces.append(compact ? "\(members.0)/\(members.1) done" : "Members done: \(members.0)/\(members.1)")
        }
        if let games {
            pieces.append(compact ? "\(games.0)/\(games.1) games" : "Games: \(games.0)/\(games.1)")
        }
        return pieces
    }
}

enum WidgetDeadlineList: Equatable {
    case userSelections
    case unpicked
    case slate
    case none
}

/// Copy and row choice for the deadline widget. The phase (`kind`) wins over stored
/// selection counts, so a timeline entry past the selection deadline shows Pickems.
enum WidgetDeadlineProgress: Equatable {
    struct Model: Equatable {
        var completionTitle: String?
        var lockTitle: String
        var countdownIsHero: Bool
        var detail: String?
        var made: Int?
        var total: Int?
        var showsBar: Bool
        var listTitle: String?
        var listEmpty: String?
        var list: WidgetDeadlineList
        var accessibilityDetail: String
        /// Make Selections subtitle. Nil outside member Selections, and when every part is missing.
        var selectionProgressLine: String? = nil
    }

    static func model(snapshot: StandingsSnapshot, kind: WidgetDeadlineKind) -> Model {
        if kind == .selections, snapshot.selectionQuota == WidgetSelectionQuota.member {
            return memberSelections(snapshot)
        }
        if kind == .selections, snapshot.selectionQuota == WidgetSelectionQuota.commissioner {
            return commissionerSlate(snapshot)
        }
        return picks(snapshot, kind: kind)
    }

    static func rows(
        snapshot: StandingsSnapshot,
        kind: WidgetDeadlineKind,
        limit: Int = 4
    ) -> [StandingsSnapshot.SnapshotGame] {
        let games = snapshot.games ?? []
        let capped = max(0, limit)
        switch model(snapshot: snapshot, kind: kind).list {
        case .none:
            return []
        case .userSelections:
            return Array(games.filter { $0.isUserSelection == true }.prefix(capped))
        case .unpicked:
            return Array(games.filter { widgetTrimmed($0.userPick) == nil && !$0.isFinal }.prefix(capped))
        case .slate:
            return Array(games.prefix(capped))
        }
    }

    private static func memberSelections(_ snapshot: StandingsSnapshot) -> Model {
        let made = max(0, snapshot.selectionsMade ?? 0)
        let total = max(0, snapshot.selectionsTotal ?? 0)
        let complete = total > 0 && made >= total
        return Model(
            completionTitle: complete ? "All selections in ✓" : nil,
            lockTitle: "Selections lock in",
            countdownIsHero: !complete,
            detail: complete || total == 0 ? nil : "\(made) of \(total) selected",
            made: total > 0 ? made : nil,
            total: total > 0 ? total : nil,
            showsBar: total > 0,
            listTitle: "Your selections",
            listEmpty: "Select your games",
            list: .userSelections,
            accessibilityDetail: complete ? "All selections in." : "\(made) of \(total) selected.",
            selectionProgressLine: WidgetSelectionProgressLine.line(snapshot: snapshot)
        )
    }

    private static func commissionerSlate(_ snapshot: StandingsSnapshot) -> Model {
        let made = max(0, snapshot.selectionsMade ?? 0)
        let total = max(0, snapshot.selectionsTotal ?? 0)
        let complete = total > 0 && made >= total
        if !complete && made == 0 {
            return Model(
                completionTitle: nil,
                lockTitle: "Selections lock in",
                countdownIsHero: true,
                detail: "Waiting on selections",
                made: nil,
                total: nil,
                showsBar: false,
                listTitle: nil,
                listEmpty: nil,
                list: .none,
                accessibilityDetail: "Waiting on selections."
            )
        }
        return Model(
            completionTitle: complete ? "Slate is set" : nil,
            lockTitle: "Selections lock in",
            countdownIsHero: !complete,
            detail: complete ? nil : "\(made) of \(total) on the slate",
            made: total > 0 ? made : nil,
            total: total > 0 ? total : nil,
            showsBar: total > 0,
            listTitle: "Slate",
            listEmpty: nil,
            list: .slate,
            accessibilityDetail: complete ? "Slate is set." : "\(made) of \(total) on the slate."
        )
    }

    private static func picks(_ snapshot: StandingsSnapshot, kind: WidgetDeadlineKind) -> Model {
        let lockTitle = kind == .selections ? "Selections lock in" : "Picks lock in"
        guard let owed = WidgetPicksOwed.owed(made: snapshot.picksMade, total: snapshot.picksTotal) else {
            return Model(
                completionTitle: nil,
                lockTitle: lockTitle,
                countdownIsHero: true,
                detail: "left",
                made: nil,
                total: nil,
                showsBar: false,
                listTitle: nil,
                listEmpty: nil,
                list: .none,
                accessibilityDetail: ""
            )
        }
        let complete = owed.left == 0
        let done = kind == .selections ? "All selections in ✓" : "All picks in ✓"
        return Model(
            completionTitle: complete ? done : nil,
            lockTitle: lockTitle,
            countdownIsHero: !complete,
            detail: complete ? nil : "\(owed.made) of \(owed.total) picked",
            made: owed.made,
            total: owed.total,
            showsBar: !complete,
            listTitle: complete ? nil : "Picks due",
            listEmpty: "Every open game has a pick",
            list: complete ? .none : .unpicked,
            accessibilityDetail: complete
                ? (kind == .selections ? "All selections in." : "All picks in.")
                : "\(owed.made) of \(owed.total) picked."
        )
    }
}

/// Live and final progress for the signed-in user's picks, from scores already on the snapshot.
enum WidgetPickProgress: Equatable {
    struct Summary: Equatable {
        var correct: Int
        var lost: Int
        var pending: Int
        var line: String
    }

    static func summarize(_ games: [StandingsSnapshot.SnapshotGame], now: Date) -> Summary? {
        let picked = games.filter { widgetTrimmed($0.userPick) != nil }
        guard !picked.isEmpty else { return nil }
        var correct = 0
        var lost = 0
        var pending = 0
        for game in picked {
            switch WidgetScoreboard.pickStatus(game, now: now) {
            case .winning, .finalWin:
                correct += 1
            case .losing, .finalLoss:
                lost += 1
            case .upcoming, .tied, .push, .noPick:
                pending += 1
            }
        }
        let settled = picked.allSatisfy(\.isFinal)
        var parts: [String] = []
        if correct > 0 { parts.append("\(correct) \(settled ? "won" : "correct")") }
        if lost > 0 { parts.append("\(lost) lost") }
        if pending > 0 { parts.append("\(pending) pending") }
        if parts.isEmpty { parts.append("0 pending") }
        return Summary(
            correct: correct,
            lost: lost,
            pending: pending,
            line: parts.joined(separator: " · ")
        )
    }

    static func pickedGames(
        _ games: [StandingsSnapshot.SnapshotGame],
        now: Date,
        limit: Int
    ) -> [StandingsSnapshot.SnapshotGame] {
        let picked = games.filter { widgetTrimmed($0.userPick) != nil }
        return WidgetScoreboard.ordered(picked, now: now, limit: limit)
    }
}

private func widgetTrimmed(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
