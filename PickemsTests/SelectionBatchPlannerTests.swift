import Foundation
import Testing
@testable import Pickems

struct SelectionBatchPlannerTests {
    @Test func acceptsFreeGamesUpToRemainingSlots() {
        let plan = SelectionBatchPlanner.plan(
            requestedIds: ["a", "b", "c"],
            takenIds: [],
            remainingSlots: 3
        )
        #expect(plan.acceptedIds == ["a", "b", "c"])
        #expect(plan.collidedIds.isEmpty)
        #expect(plan.droppedForLimit.isEmpty)
    }

    @Test func marksGamesTakenSinceBrowseOpenedAsCollided() {
        let plan = SelectionBatchPlanner.plan(
            requestedIds: ["a", "b", "c"],
            takenIds: ["b"],
            remainingSlots: 3
        )
        #expect(plan.acceptedIds == ["a", "c"])
        #expect(plan.collidedIds == ["b"])
        #expect(plan.droppedForLimit.isEmpty)
    }

    @Test func dropsExtrasPastRemainingQuota() {
        let plan = SelectionBatchPlanner.plan(
            requestedIds: ["a", "b", "c"],
            takenIds: [],
            remainingSlots: 2
        )
        #expect(plan.acceptedIds == ["a", "b"])
        #expect(plan.droppedForLimit == ["c"])
    }

    @Test func collisionConsumesNoSlot() {
        let plan = SelectionBatchPlanner.plan(
            requestedIds: ["taken", "free"],
            takenIds: ["taken"],
            remainingSlots: 1
        )
        #expect(plan.acceptedIds == ["free"])
        #expect(plan.collidedIds == ["taken"])
    }

    @Test func dedupesRequestedIds() {
        let plan = SelectionBatchPlanner.plan(
            requestedIds: ["a", "a", "b"],
            takenIds: [],
            remainingSlots: 2
        )
        #expect(plan.acceptedIds == ["a", "b"])
    }

    @Test func collisionMessageNamesTakenGames() {
        let partial = SelectionBrowseSaveResult(
            savedEventIds: ["a"],
            collidedEventIds: ["b"],
            collidedLabels: ["ALA @ AUB"]
        )
        #expect(partial.collisionMessage == "ALA @ AUB was already taken. Your other Selections were saved.")

        let allTaken = SelectionBrowseSaveResult(
            savedEventIds: [],
            collidedEventIds: ["b", "c"],
            collidedLabels: ["ALA @ AUB", "OSU @ MICH"]
        )
        #expect(
            allTaken.collisionMessage
                == "ALA @ AUB and OSU @ MICH were already taken. Pick different games."
        )
    }
}
