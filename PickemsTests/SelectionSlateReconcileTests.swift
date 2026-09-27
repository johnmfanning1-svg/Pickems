import Foundation
import Testing
@testable import Pickems

struct SelectionSlateReconcileTests {
    @Test func expandsToExpectedWhenMembershipGrows() {
        // Core 4 W4: 3×3=9 minted, 4th member joins → expect 12.
        let target = SelectionSlateReconcile.targetSlateSize(
            expected: 12,
            currentSlateSize: 9,
            takenUniqueGames: 9
        )
        #expect(target == 12)
    }

    @Test func neverShrinksBelowTakenGames() {
        let target = SelectionSlateReconcile.targetSlateSize(
            expected: 9,
            currentSlateSize: 12,
            takenUniqueGames: 11
        )
        #expect(target == 11)
    }

    @Test func canShrinkTowardExpectedWhenRoomExists() {
        let target = SelectionSlateReconcile.targetSlateSize(
            expected: 9,
            currentSlateSize: 12,
            takenUniqueGames: 7
        )
        #expect(target == 9)
    }

    @Test func effectiveSlatePrefersExpectedOverStaleWeekSnapshot() {
        let effective = SelectionSlateReconcile.effectiveSlateSize(
            weekSlateSize: 9,
            expected: 12
        )
        #expect(effective == 12)
        #expect(
            SelectionSlateReconcile.remainingSlateSlots(slateSize: effective, takenUniqueGames: 9) == 3
        )
    }

    @Test func pickErrorCopySplitsPersonalLimitFromSlateFull() {
        #expect(
            PickService.PickError.nominationLimitReached.errorDescription
                == "You've reached your Selection limit."
        )
        #expect(
            PickService.PickError.slateFull.errorDescription
                == "The league slate is full — no Selection slots left this week."
        )
        #expect(
            PickService.PickError.selectionClosed.errorDescription
                == "Selections can't be changed after the Selection deadline."
        )
    }
}
