import Foundation
import Testing
@testable import Pickems

/// Commissioner reopen + deadline editor wiring.
struct ReopenSelectionsDeadlineFlowTests {
    @Test func selectionEditReopenFlagDefaultsFalse() {
        let edit = SelectionDeadlineEdit(
            capture: DeadlineEditCapture(
                groupId: "g",
                weekId: "2026-W1",
                weekLabel: "Week 1",
                isRollingLock: false
            ),
            initialDeadline: nil
        )
        #expect(!edit.reopenOnSave)
    }

    @Test func reopenFlowEditSetsReopenOnSave() {
        let edit = SelectionDeadlineEdit(
            capture: DeadlineEditCapture(
                groupId: "g",
                weekId: "2026-W1",
                weekLabel: "Week 1",
                isRollingLock: false
            ),
            initialDeadline: nil,
            reopenOnSave: true
        )
        #expect(edit.reopenOnSave)
        #expect(edit.initialDeadline == nil)
    }
}