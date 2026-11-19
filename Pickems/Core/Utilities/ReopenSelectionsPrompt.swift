import Foundation

/// Reopen Selections confirm copy and write target for commissioner Settings.
enum ReopenSelectionsPrompt {
    static let title = "Reopen Selections?"
    static let message =
        "Members can add and remove Selections again. Pickems close until you open the week."
    static let confirmTitle = "Reopen Selections"

    static let weekUnavailableMessage =
        "Selections can't be reopened for this week right now."

    static let leagueUnavailableMessage =
        "That league isn't available right now. Pull to refresh and try again."

    static let signInRequiredMessage = "Sign in to continue."

    static let deadlineSaveFailedAfterReopenMessage =
        "Selections reopened, but the new deadline didn't save. Set it in Selection Deadline."

    /// Firestore rules on `main` allow only isolated week-field sets (see `weekOperatorFieldUpdate`).
    /// Status reopen and `selectionDeadline` cannot ship in one client update, so the app reopens,
    /// sets the deadline, then clears the materialized slate.
    enum WriteStep: Equatable, CaseIterable {
        case reopenWeek
        case setDeadline
        case clearSlate
    }

    static let writeStepsWithDeadline: [WriteStep] = [.reopenWeek, .setDeadline, .clearSlate]

    /// Frozen at tap from the pinned settings league, not `selectedGroup`.
    static func writeTarget(settingsGroupId: String, week: WeekSummary) -> (groupId: String, weekId: String)? {
        guard WeekTransition.canReopenSelections(week) else { return nil }
        return (settingsGroupId, week.id)
    }

    /// At confirm time, re-read the pinned week and require the same id and reopenable status.
    static func confirmWriteTarget(
        settingsGroupId: String,
        pinnedWeekId: String,
        liveWeek: WeekSummary?
    ) -> (groupId: String, weekId: String)? {
        guard let liveWeek, liveWeek.id == pinnedWeekId else { return nil }
        return writeTarget(settingsGroupId: settingsGroupId, week: liveWeek)
    }

    static func captureForReopenDeadline(
        settingsGroupId: String,
        week: WeekSummary
    ) -> DeadlineEditCapture? {
        guard writeTarget(settingsGroupId: settingsGroupId, week: week) != nil else { return nil }
        return DeadlineEditCapture(
            groupId: settingsGroupId,
            weekId: week.id,
            weekLabel: week.displayLabel,
            isRollingLock: week.isRollingLock
        )
    }

    /// Future default for the post-reopen deadline editor (selections still closed).
    static func defaultReopenDeadline(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: 48, to: now) ?? now.addingTimeInterval(48 * 3600)
    }
}