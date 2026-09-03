import Foundation
import FirebaseFirestore

enum WeekTransition {
    /// Builds Firestore fields when a week moves into the picking phase.
    /// Filling the slate sets `pickDeadline` from the earliest kickoff but does **not**
    /// freeze the slate — games stay swappable until that deadline (or commissioner early lock).
    static func toPickingUpdates(
        rules: GroupRules,
        games: [(id: String, kickoff: Date)],
        nominationCount: Int? = nil,
        setDeadline: Bool = true,
        lockSlate: Bool = false
    ) -> [String: Any] {
        var updates: [String: Any] = [
            "status": WeekStatus.picking.rawValue
        ]

        if let nominationCount {
            updates[FirestoreField.nominationCount] = nominationCount
        }

        if setDeadline || lockSlate {
            for (key, value) in lockSnapshotFields(rules: rules, games: games) {
                updates[key] = value
            }
        }

        if lockSlate {
            // Audit stamp that the slate was closed by the commissioner.
            // Do not zero pickDeadline — members still need time until first kickoff.
            updates["lockedAt"] = Timestamp(date: Date())
        }

        return updates
    }

    /// Test / kickoff-only convenience. Prefer the `games:` overload in production.
    static func toPickingUpdates(
        rules: GroupRules,
        kickoffs: [Date],
        nominationCount: Int? = nil,
        setDeadline: Bool = true,
        lockSlate: Bool = false
    ) -> [String: Any] {
        toPickingUpdates(
            rules: rules,
            games: kickoffs.enumerated().map { ("game-\($0.offset)", $0.element) },
            nominationCount: nominationCount,
            setDeadline: setDeadline,
            lockSlate: lockSlate
        )
    }

    /// Snapshot lock policy onto the week so later rule changes do not rewrite an in-progress week.
    static func lockSnapshotFields(
        rules: GroupRules,
        games: [(id: String, kickoff: Date)]
    ) -> [String: Any] {
        let mode: DeadlinePolicy = rules.pickDeadline == .rolling ? .rolling : .firstKickoff
        let capped = Array(games.prefix(20))
        var fields: [String: Any] = [
            "pickLockMode": mode.rawValue
        ]
        guard let first = capped.map(\.kickoff).min(),
              let last = capped.map(\.kickoff).max() else {
            return fields
        }

        var gameKickoffs: [String: Timestamp] = [:]
        var gameIds: [String] = []
        for game in capped {
            gameIds.append(game.id)
            gameKickoffs[game.id] = Timestamp(date: game.kickoff)
        }

        fields["pickDeadline"] = Timestamp(date: first)
        fields["weekLockAt"] = Timestamp(date: mode == .rolling ? last : first)
        fields["gameIds"] = gameIds
        fields["gameKickoffs"] = gameKickoffs
        return fields
    }

    /// Commissioner opens picking early (end nomination) — pick deadline stays first kickoff.
    static func lockEarlyUpdates(rules: GroupRules, games: [(id: String, kickoff: Date)]) -> [String: Any] {
        toPickingUpdates(rules: rules, games: games, setDeadline: true, lockSlate: true)
    }

    static func lockEarlyUpdates(rules: GroupRules, kickoffs: [Date]) -> [String: Any] {
        toPickingUpdates(rules: rules, kickoffs: kickoffs, setDeadline: true, lockSlate: true)
    }

    /// Commissioner returns a week to the Selection phase so members can remake.
    /// Clears the lock-early stamp. Caller also clears a passed Selection deadline
    /// so remake is allowed and the scheduled job cannot immediately re-open Pickems.
    static func toSelectionUpdates() -> [String: Any] {
        [
            "status": WeekStatus.selection.rawValue,
            "lockedAt": FieldValue.delete(),
        ]
    }

    /// Reopen Selections while Pickems have opened but the week is not scored.
    static func canReopenSelections(_ week: WeekSummary) -> Bool {
        if week.skipsSelection { return false }
        switch week.status {
        case .picking, .locked: return true
        case .selection, .scored: return false
        }
    }

    /// Completing Selections never opens Pickems. Only the Selection deadline
    /// (Cloud Function) or commissioner lock-early (`lockEarlyUpdates`) flips status.
    static var opensPickingWhenSlateFills: Bool { false }

    /// Commissioner can add, replace, or remove any member's Selections while
    /// the week is still in `.selection` (including after the member deadline).
    static func commissionerCanManageSelections(_ week: WeekSummary) -> Bool {
        guard !week.skipsSelection else { return false }
        return week.status == .selection
    }

    /// Members can add/remove Selections while the week is still in `.selection`
    /// and the Selection deadline has not passed. After lock-early or deadline,
    /// status is `.picking` and Selections are frozen.
    static func canRemakeSelections(_ week: WeekSummary, now: Date = Date()) -> Bool {
        guard !week.skipsSelection else { return false }
        guard week.status == .selection else { return false }
        if let deadline = week.selectionDeadline {
            return now < deadline
        }
        return true
    }

    /// Pickems are available only after the week leaves `.selection`.
    static func arePickemsOpen(_ week: WeekSummary) -> Bool {
        switch week.status {
        case .picking, .locked, .scored: return true
        case .selection: return false
        }
    }

    /// Game G is frozen for member edits.
    static func isGameLocked(_ game: SlateGame, week: WeekSummary, now: Date = Date()) -> Bool {
        isGameLocked(gameId: game.id, kickoff: game.kickoff, week: week, now: now)
    }

    static func isGameLocked(
        gameId: String,
        kickoff: Date,
        week: WeekSummary,
        now: Date = Date()
    ) -> Bool {
        switch week.status {
        case .selection, .locked, .scored:
            return true
        case .picking:
            break
        }
        if let remaining = week.remainingLockAt, now >= remaining {
            return true
        }
        if week.isRollingLock {
            if let stamped = week.gameKickoffs?[gameId] {
                return now >= stamped
            }
            return now >= kickoff
        }
        if let deadline = week.pickDeadline {
            return now >= deadline
        }
        return false
    }

    /// True when no remaining games can be edited (rolling: last kickoff / remaining freeze).
    static func arePicksFullyLocked(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .locked, .scored, .selection:
            return true
        case .picking:
            if week.isRollingLock {
                if let remaining = week.remainingLockAt, now >= remaining { return true }
                if let weekLockAt = week.weekLockAt { return now >= weekLockAt }
                return false
            }
            return PickDeadlineCalculator.isPast(week.pickDeadline, now: now)
        }
    }

    /// League chart is visible: full slate after first-kickoff lock, or partial board
    /// once any rolling game has locked.
    static func pickemsShouldShowLeagueBoard(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .locked, .scored:
            return true
        case .picking:
            if week.isRollingLock {
                if let remaining = week.remainingLockAt, now >= remaining { return true }
                return PickDeadlineCalculator.isPast(week.pickDeadline, now: now)
            }
            return PickDeadlineCalculator.isPast(week.pickDeadline, now: now)
        case .selection:
            return false
        }
    }

    /// Other members' full pick documents are readable (week fully locked).
    static func pickemsAreFullyPublic(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .locked, .scored:
            return true
        case .picking:
            if week.isRollingLock {
                return arePicksFullyLocked(week, now: now)
            }
            return PickDeadlineCalculator.isPast(week.pickDeadline, now: now)
        case .selection:
            return false
        }
    }

    /// Abandon the picking UI for the full locked/scored chart.
    static func pickemsShouldShowFullLockedPhase(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .locked, .scored:
            return true
        case .picking:
            return arePicksFullyLocked(week, now: now)
        case .selection:
            return false
        }
    }

    /// Slate games/noms can change during selection, or during picking before the pick deadline.
    /// Past weeks already stamped with a fill-time `lockedAt` stay editable until `pickDeadline`.
    /// Locked/scored weeks are never editable, even if `pickDeadline` is still in the future.
    static func isSlateEditable(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .selection:
            return canRemakeSelections(week, now: now)
        case .picking:
            if week.isRollingLock {
                // Adding/removing games after the first kickoff would rewrite lock snapshots.
                if let deadline = week.pickDeadline {
                    return now < deadline
                }
                return true
            }
            if let deadline = week.pickDeadline {
                return now < deadline
            }
            return true
        case .locked, .scored:
            return false
        }
    }

    /// Spread Pickems can be edited while the week is picking and at least one game is open.
    static func arePicksEditable(_ week: WeekSummary, now: Date = Date()) -> Bool {
        switch week.status {
        case .picking:
            return !arePicksFullyLocked(week, now: now)
        case .selection, .locked, .scored:
            return false
        }
    }
}
