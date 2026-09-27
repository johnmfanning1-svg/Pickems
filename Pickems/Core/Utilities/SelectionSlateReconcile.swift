import Foundation

/// Pure helpers for member-mode slate capacity during `.selection`.
enum SelectionSlateReconcile {
    /// Target `week.slateSize` after membership/rules change.
    /// Expands up to `expected`; never shrinks below games already claimed.
    static func targetSlateSize(expected: Int, currentSlateSize: Int, takenUniqueGames: Int) -> Int {
        let expectedFloor = max(expected, 1)
        let takenFloor = max(takenUniqueGames, 0)
        if expectedFloor >= currentSlateSize {
            return expectedFloor
        }
        // Shrinking (rules/membership down): keep room for filled slots.
        return max(expectedFloor, takenFloor)
    }

    /// Effective slate cap for client remaining-slot math when the week snapshot may lag.
    static func effectiveSlateSize(weekSlateSize: Int, expected: Int) -> Int {
        max(max(weekSlateSize, 0), max(expected, 1))
    }

    /// Remaining unique games the league can still accept.
    static func remainingSlateSlots(slateSize: Int, takenUniqueGames: Int) -> Int {
        max(slateSize - max(takenUniqueGames, 0), 0)
    }
}
