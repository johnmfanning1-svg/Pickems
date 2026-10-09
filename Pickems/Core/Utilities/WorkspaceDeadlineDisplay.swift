import Foundation

/// Which workspace is asking for the week’s deadline header.
enum WorkspaceDeadlineKind: Equatable {
    case selections
    case pickems
}

/// Deadlines to pin at the top of Selections and Pickems.
struct WorkspaceDeadlineSnapshot: Equatable {
    /// Member nomination deadline when this week has a Selection phase.
    var selectionDeadline: Date?
    /// Next Pickems lock (rolling next kickoff, remaining freeze, or slate deadline).
    var pickemsDeadline: Date?
    var isRolling: Bool
    var openCount: Int
    var totalCount: Int
    /// Commissioner-only prompt when Selections still need a deadline.
    var showSetSelectionDeadlinePrompt: Bool
    /// Commissioner-only: Pickems are open with no stored lock, so the countdown
    /// is the first-kickoff fallback and asks the commissioner to set one.
    var showSetPickemsDeadlinePrompt: Bool = false
    /// Selections row. Countdown only while `.open`. Nil when the week skips Selections.
    var selectionState: SelectionDeadlineDisplay? = nil

    var hasContent: Bool {
        switch selectionState {
        case .open, .locked:
            return true
        case .needsDeadline:
            return showSetSelectionDeadlinePrompt || pickemsDeadline != nil
        case nil:
            return pickemsDeadline != nil || showSetSelectionDeadlinePrompt
        }
    }

    /// A Selection countdown or a Pickems lock is still moving.
    /// A locked Selections row does not keep the clock alive by itself.
    var clockIsLive: Bool {
        if case .open = selectionState { return true }
        return pickemsDeadline != nil
    }

    /// True when the row for `deadline` is asking the commissioner to set it.
    /// Only those rows are tappable (they open the deadline editor).
    func isPromptingCommissioner(for deadline: WorkspaceDeadlineKind) -> Bool {
        switch deadline {
        case .selections: return showSetSelectionDeadlinePrompt
        case .pickems: return showSetPickemsDeadlinePrompt && pickemsDeadline != nil
        }
    }
}

/// Where a tapped deadline prompt should land: the deadline editor in
/// Commissioner Settings for this league and week.
struct CommissionerDeadlineTarget: Equatable {
    var kind: WorkspaceDeadlineKind
    var groupId: String?
    /// Nil means the league's current week (push links don't carry a week).
    var weekId: String?

    /// Commissioner Settings for `groupId` opens the editor only for the same league.
    func matches(groupId otherGroupId: String) -> Bool {
        groupId == nil || groupId == otherGroupId
    }
}

enum WorkspaceDeadlineDisplay {
    static func snapshot(
        kind: WorkspaceDeadlineKind,
        week: WeekSummary,
        isCommissioner: Bool,
        games: [SlateGame],
        now: Date = Date()
    ) -> WorkspaceDeadlineSnapshot {
        let selectionState = SelectionDeadlineDisplayResolver.resolve(week: week, now: now)
        // Stored deadline, including after Selections close. Count down only when `selectionState` is `.open`.
        let selection: Date? = week.skipsSelection ? nil : week.selectionDeadline
        let pickemsOpen = WeekTransition.arePickemsOpen(week)
        let rollingLive = pickemsOpen && week.isRollingLock
        let pickems = pickemsDeadline(week: week, games: games, now: now)
        let ask: WorkspaceDeadlineKind? = commissionerPrompt(
            kind: kind,
            week: week,
            isCommissioner: isCommissioner,
            now: now
        )

        return WorkspaceDeadlineSnapshot(
            selectionDeadline: selection,
            pickemsDeadline: pickems,
            isRolling: rollingLive,
            openCount: rollingLive
                ? PickDeadlineCalculator.openGameCount(week: week, games: games, now: now)
                : 0,
            totalCount: rollingLive ? games.count : 0,
            showSetSelectionDeadlinePrompt: ask == .selections,
            showSetPickemsDeadlinePrompt: ask == .pickems,
            selectionState: selectionState
        )
    }

    /// Which deadline (if any) this tab's header asks the commissioner to set.
    /// - Selections tab: Selections are still open with no Selection deadline.
    /// - Pickems tab: Pickems are open (not rolling) with no stored Pickems lock.
    static func commissionerPrompt(
        kind: WorkspaceDeadlineKind,
        week: WeekSummary,
        isCommissioner: Bool,
        now: Date = Date()
    ) -> WorkspaceDeadlineKind? {
        guard isCommissioner else { return nil }
        switch kind {
        case .selections:
            let needsSelectionDeadline = SelectionDeadlineDisplayResolver.resolve(week: week, now: now) == .needsDeadline
            return needsSelectionDeadline ? .selections : nil
        case .pickems:
            let needsPickemsDeadline: Bool = week.status == .picking
                && !week.isRollingLock
                && week.pickDeadline == nil
            return needsPickemsDeadline ? .pickems : nil
        }
    }

    /// During Selections, stamp first-kickoff as the Pickems lock. After Pickems
    /// open, rolling weeks advance to the next remaining kickoff.
    static func pickemsDeadline(
        week: WeekSummary,
        games: [SlateGame],
        now: Date = Date()
    ) -> Date? {
        if WeekTransition.arePickemsOpen(week), week.isRollingLock {
            return PickDeadlineCalculator.nextLockDate(week: week, games: games, now: now)
                ?? week.pickDeadline
        }
        if let stored = week.pickDeadline {
            return stored
        }
        // Before the week snapshots a lock, show the deadline that will apply:
        // first kickoff. Rolling advances to the next game only after Pickems open.
        return games.map(\.kickoff).min()
    }
}
