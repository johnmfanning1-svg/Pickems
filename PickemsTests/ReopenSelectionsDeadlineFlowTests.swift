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
        let seed = ReopenSelectionsPrompt.defaultReopenDeadline()
        let edit = SelectionDeadlineEdit(
            capture: DeadlineEditCapture(
                groupId: "g",
                weekId: "2026-W1",
                weekLabel: "Week 1",
                isRollingLock: false
            ),
            initialDeadline: seed,
            reopenOnSave: true
        )
        #expect(edit.reopenOnSave)
        #expect(edit.initialDeadline == seed)
    }

    @Test func writeStepsWithDeadlineOrderReopenSetDeadlineThenClearSlate() {
        #expect(ReopenSelectionsPrompt.writeStepsWithDeadline == [
            .reopenWeek,
            .setDeadline,
            .clearSlate,
        ])
    }

    @Test func deadlineSaveFailedMessageGuidesCommissioner() {
        let message = ReopenSelectionsPrompt.deadlineSaveFailedAfterReopenMessage
        #expect(message.localizedCaseInsensitiveContains("reopened"))
        #expect(message.localizedCaseInsensitiveContains("Selection Deadline"))
    }

    @Test func writerStopsBeforeClearSlateWhenDeadlineSaveFails() async throws {
        var clearSlateCalled = false
        let outcome = try await ReopenSelectionsWriter.perform(
            deadline: Date(),
            groupId: "g1",
            weekId: "2026-W1",
            userId: "u1",
            commissionerName: "Commissioner",
            reopenWeekForSelections: { _, _ in },
            setSelectionDeadline: { _, _, _, _ in
                struct TestFailure: Error {}
                throw TestFailure()
            },
            clearSlateGamesForSelectionReopen: { _, _, _, _ in
                clearSlateCalled = true
            }
        )
        #expect(outcome == .deadlineSaveFailed)
        #expect(!clearSlateCalled)
    }
}