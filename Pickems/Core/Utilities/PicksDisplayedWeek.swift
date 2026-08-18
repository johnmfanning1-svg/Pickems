import Foundation

/// Which week Selections vs Pickems should render while `GroupService.currentWeek` is shared.
enum PicksDisplayedWeek {
    /// Pickems never shows a future week, even if Selections still has one pinned.
    static func resolve(
        current: WeekSummary?,
        hideFuture: Bool,
        available: [WeekSummary],
        activeWeekId: String?,
        isFuture: (WeekSummary) -> Bool
    ) -> WeekSummary? {
        guard let current else { return nil }
        guard hideFuture, isFuture(current) else { return current }
        if let activeWeekId, let match = available.first(where: { $0.id == activeWeekId }) {
            return match
        }
        return available.last(where: { !isFuture($0) }) ?? current
    }
}
