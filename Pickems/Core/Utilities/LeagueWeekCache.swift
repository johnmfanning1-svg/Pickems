import Foundation
import FirebaseFirestore

/// In-memory week lists for the league on screen.
///
/// Week document ids (`2026-W7`) are the same in every league. A deadline write
/// for one league must not stamp `currentWeek` or the week chips of another
/// just because the ids match.
enum LeagueWeekCache {
    static func update(
        observedGroupId: String?,
        availableWeeksGroupId: String?,
        currentWeek: inout WeekSummary?,
        availableWeeks: inout [WeekSummary],
        groupId: String,
        weekId: String,
        mutate: (inout WeekSummary) -> Void
    ) {
        if observedGroupId == groupId, var week = currentWeek, week.id == weekId {
            mutate(&week)
            currentWeek = week
        }
        if availableWeeksGroupId == groupId,
           let index = availableWeeks.firstIndex(where: { $0.id == weekId }) {
            mutate(&availableWeeks[index])
        }
    }
}

/// League and week the deadline editor was opened for.
///
/// Save uses this capture. The league selected when the button fires is ignored:
/// week ids are shared, so "whatever is selected now" can be a different league.
struct DeadlineEditCapture: Equatable {
    var groupId: String
    var weekId: String
    var weekLabel: String
    var isRollingLock: Bool

    func writeTarget(
        selectedGroupId: String?,
        selectedWeekId: String?
    ) -> (groupId: String, weekId: String) {
        // Touch the live ids so call sites pass them, and so this stays the
        // place that decides they do not win — including when the week id matches.
        if selectedGroupId == groupId, selectedWeekId == weekId {
            return (groupId, weekId)
        }
        return (groupId, weekId)
    }
}

struct SelectionDeadlineEdit: Equatable {
    var capture: DeadlineEditCapture
    var initialDeadline: Date?
}

struct PickDeadlineEdit: Equatable {
    var capture: DeadlineEditCapture
    var weekStatus: WeekStatus
    var initialDeadline: Date?
    var isPastDeadline: Bool
}

enum SelectionDeadlineLocal {
    static func apply(
        deadline: Date,
        setAt: Date,
        setBy: String,
        to week: inout WeekSummary
    ) {
        week.selectionDeadline = deadline
        week.selectionDeadlineSetAt = setAt
        week.selectionDeadlineSetBy = setBy
    }

    /// Reopen Selections: drop the deadline so the week is open in this league only.
    static func clear(on week: inout WeekSummary) {
        week.status = .selection
        week.lockedAt = nil
        week.selectionDeadline = nil
        week.selectionDeadlineSetAt = nil
        week.selectionDeadlineSetBy = nil
    }
}

/// Pickems deadline field choice follows the week the editor captured, not the
/// week currently on screen (which may be another league with the same id).
enum PickDeadlineWrite {
    static func fieldName(isRollingLock: Bool) -> String {
        isRollingLock ? "remainingLockAt" : "pickDeadline"
    }

    static func firestoreFields(deadline: Date, isRollingLock: Bool) -> [String: Any] {
        [fieldName(isRollingLock: isRollingLock): Timestamp(date: deadline)]
    }

    static func apply(deadline: Date, isRollingLock: Bool, to week: inout WeekSummary) {
        if isRollingLock {
            week.remainingLockAt = deadline
        } else {
            week.pickDeadline = deadline
        }
    }
}
