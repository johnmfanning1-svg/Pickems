import Foundation

/// What a Commissioner Settings row asked to open.
///
/// Deadline, Selections, Slate, and tie rows carry the week chip that was tapped.
/// `GroupService.currentWeek` is not part of this value: the sheet can present
/// before that property is visible, which showed "No Active Week" in 3.6.6.
enum CommissionerSheetRequest: Equatable {
    case selectionDeadline(WeekSummary)
    case pickDeadline(WeekSummary)
    case adminGameBrowse
    case members
    case selections(WeekSummary)
    case slate(WeekSummary)
    case rankTies(TieRankDraft, WeekSummary)
}

/// Builds the `CommissionerSheet` item `.sheet(item:)` presents.
///
/// The item owns the week. Sheet content reads that item, not a second `@State`
/// set in the same tap (`selectionDeadlineEdit` / `pickDeadlineEdit`). That
/// sibling was still nil on the presentation frame, so the date picker never
/// appeared for the current or a future week.
enum CommissionerDeadlinePresentation {
    /// Nil when the carousel week belongs to a different league than this
    /// Settings screen. Members and game browse do not need a week.
    static func route(
        for request: CommissionerSheetRequest,
        settingsGroupId: String,
        selectedGroupId: String?
    ) -> CommissionerSheet? {
        switch request {
        case .adminGameBrowse:
            return .adminGameBrowse
        case .members:
            return .members
        case .selectionDeadline(let week):
            guard selectedGroupId == settingsGroupId else { return nil }
            return .selectionDeadline(selectionEdit(settingsGroupId: settingsGroupId, week: week))
        case .pickDeadline(let week):
            guard selectedGroupId == settingsGroupId else { return nil }
            return .pickDeadline(pickEdit(settingsGroupId: settingsGroupId, week: week))
        case .selections(let week):
            guard selectedGroupId == settingsGroupId else { return nil }
            return .selections(week)
        case .slate(let week):
            guard selectedGroupId == settingsGroupId else { return nil }
            return .slate(week)
        case .rankTies(let draft, let week):
            guard selectedGroupId == settingsGroupId else { return nil }
            return .rankTies(draft, capture(settingsGroupId: settingsGroupId, week: week))
        }
    }

    static func selectionEdit(settingsGroupId: String, week: WeekSummary) -> SelectionDeadlineEdit {
        SelectionDeadlineEdit(
            capture: capture(settingsGroupId: settingsGroupId, week: week),
            initialDeadline: week.selectionDeadline
        )
    }

    static func pickEdit(settingsGroupId: String, week: WeekSummary) -> PickDeadlineEdit {
        let initialDeadline: Date? = week.isRollingLock
            ? (week.remainingLockAt ?? week.effectiveWeekLockAt ?? week.pickDeadline)
            : week.pickDeadline
        return PickDeadlineEdit(
            capture: capture(settingsGroupId: settingsGroupId, week: week),
            weekStatus: week.status,
            initialDeadline: initialDeadline,
            isPastDeadline: WeekTransition.arePicksFullyLocked(week)
        )
    }

    /// Push / countdown deep link. `weekId` wins even when the week document
    /// has not loaded (`displayedWeek == nil`).
    static func pendingSelection(
        settingsGroupId: String,
        weekId: String,
        displayedWeek: WeekSummary?
    ) -> CommissionerSheet {
        .selectionDeadline(
            SelectionDeadlineEdit(
                capture: DeadlineEditCapture(
                    groupId: settingsGroupId,
                    weekId: weekId,
                    weekLabel: displayedWeek?.displayLabel ?? "This week",
                    isRollingLock: displayedWeek?.isRollingLock ?? false
                ),
                initialDeadline: displayedWeek?.selectionDeadline
            )
        )
    }

    /// Editor the Selection sheet shows.
    ///
    /// `siblingEdit` is the old `@State` slot. It is ignored, including when it
    /// is nil: that nil is what filled the sheet with "No Active Week".
    static func presentedSelectionEdit(
        on route: CommissionerSheet,
        siblingEdit _: SelectionDeadlineEdit?
    ) -> SelectionDeadlineEdit? {
        guard case .selectionDeadline(let edit) = route else { return nil }
        return edit
    }

    /// Editor the Pickems sheet shows. `siblingEdit` is ignored. See `presentedSelectionEdit`.
    static func presentedPickEdit(
        on route: CommissionerSheet,
        siblingEdit _: PickDeadlineEdit?
    ) -> PickDeadlineEdit? {
        guard case .pickDeadline(let edit) = route else { return nil }
        return edit
    }

    private static func capture(settingsGroupId: String, week: WeekSummary) -> DeadlineEditCapture {
        DeadlineEditCapture(
            groupId: settingsGroupId,
            weekId: week.id,
            weekLabel: week.displayLabel,
            isRollingLock: week.isRollingLock
        )
    }
}
