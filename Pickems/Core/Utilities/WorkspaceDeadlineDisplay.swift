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

    var hasContent: Bool {
        selectionDeadline != nil
            || pickemsDeadline != nil
            || showSetSelectionDeadlinePrompt
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
        let selection: Date? = week.skipsSelection ? nil : week.selectionDeadline
        let pickemsOpen = WeekTransition.arePickemsOpen(week)
        let rollingLive = pickemsOpen && week.isRollingLock
        let pickems = pickemsDeadline(week: week, games: games, now: now)
        let prompt = kind == .selections
            && isCommissioner
            && week.status == .selection
            && !week.skipsSelection
            && week.selectionDeadline == nil

        return WorkspaceDeadlineSnapshot(
            selectionDeadline: selection,
            pickemsDeadline: pickems,
            isRolling: rollingLive,
            openCount: rollingLive
                ? PickDeadlineCalculator.openGameCount(week: week, games: games, now: now)
                : 0,
            totalCount: rollingLive ? games.count : 0,
            showSetSelectionDeadlinePrompt: prompt
        )
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
        return week.pickDeadline
    }
}
