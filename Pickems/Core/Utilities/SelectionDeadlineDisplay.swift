import Foundation

/// How the Selections deadline row should read.
///
/// `.open` is the only countdown. Locked and closed weeks are static so the row
/// cannot disagree with the "Selections are locked" banner.
enum SelectionDeadlineDisplay: Equatable {
    /// Deadline is set and Selections are still open.
    case open(deadline: Date)
    /// Selections are open and no deadline is set. Commissioners see the set prompt.
    case needsDeadline
    /// Static locked or closed copy. No timer and no set-deadline prompt.
    case locked(SelectionLockCopy)

    var isCountingDown: Bool {
        if case .open = self { return true }
        return false
    }
}

struct SelectionLockCopy: Equatable {
    /// Primary line under the Selections eyebrow. Always "Locked".
    var title: String
    /// Optional second line, such as "Locked when slate filled" or "Closed Sat, Oct 10, 5:13 PM".
    var detail: String?

    /// Single line for Commissioner Settings and other compact rows.
    var compact: String {
        detail ?? title
    }
}

enum SelectionDeadlineDisplayResolver {
    /// Nil when this week has no Selection phase (Week 0).
    static func resolve(week: WeekSummary, now: Date = Date()) -> SelectionDeadlineDisplay? {
        guard !week.skipsSelection else { return nil }
        if isClosed(week, now: now) {
            return .locked(lockCopy(week: week, now: now))
        }
        if let deadline = week.selectionDeadline {
            return .open(deadline: deadline)
        }
        return .needsDeadline
    }

    /// Closed whenever the lock banner would show, and also once the Selection
    /// deadline has passed (the status flip to Pickems can lag the clock).
    static func isClosed(_ week: WeekSummary, now: Date = Date()) -> Bool {
        if WeekTransition.showsSelectionsLockedBanner(week) { return true }
        guard let deadline = week.selectionDeadline else { return false }
        return now >= deadline
    }

    private static func lockCopy(week: WeekSummary, now: Date) -> SelectionLockCopy {
        if let deadline = week.selectionDeadline, now >= deadline {
            let closed = "Closed \(PickDeadlineCalculator.lockTimeLabel(for: deadline))"
            return SelectionLockCopy(title: "Locked", detail: closed)
        }
        // Still before the deadline, but Pickems already opened without a commissioner lock.
        if week.status == .picking, week.lockedAt == nil {
            return SelectionLockCopy(title: "Locked", detail: "Locked when slate filled")
        }
        return SelectionLockCopy(title: "Locked", detail: nil)
    }
}
