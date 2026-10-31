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

    private static func leagueURL(groupId: String, weekId: String, tail: String) -> URL? {
        var components = URLComponents()
        components.scheme = "pickems"
        components.host = "league"
        components.path = "/\(groupId)/week/\(weekId)/\(tail)"
        return components.url
    }
}
