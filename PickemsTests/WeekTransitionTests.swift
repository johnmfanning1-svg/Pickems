import Foundation
import Testing
@testable import Pickems

struct WeekTransitionTests {
    private func week(
        status: WeekStatus,
        deadline: Date? = nil,
        lockedAt: Date? = nil
    ) -> WeekSummary {
        WeekSummary(
            id: "2026-W1",
            seasonYear: 2026,
            weekNumber: 1,
            status: status,
            slateSize: 5,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: lockedAt,
            pickDeadline: deadline,
            nominationCount: 5
        )
    }

    @Test func slateEditableDuringSelection() {
        #expect(WeekTransition.isSlateEditable(week(status: .selection)))
    }

    @Test func slateEditableDuringPickingBeforeDeadline() {
        let deadline = Date().addingTimeInterval(7 * 24 * 3600)
        #expect(WeekTransition.isSlateEditable(week(status: .picking, deadline: deadline)))
    }

    @Test func slateEditableIgnoresStaleLockedAtWhenDeadlineFuture() {
        // Old fill behavior stamped lockedAt immediately; deadline is still weeks out.
        let deadline = Date().addingTimeInterval(14 * 24 * 3600)
        let lockedAt = Date().addingTimeInterval(-60)
        #expect(WeekTransition.isSlateEditable(
            week(status: .picking, deadline: deadline, lockedAt: lockedAt)
        ))
    }

    @Test func slateNotEditableAfterDeadline() {
        let deadline = Date().addingTimeInterval(-60)
        #expect(!WeekTransition.isSlateEditable(week(status: .picking, deadline: deadline)))
    }

    @Test func slateNotEditableWhenLockedOrScored() {
        #expect(!WeekTransition.isSlateEditable(week(status: .locked)))
        #expect(!WeekTransition.isSlateEditable(week(status: .scored)))
    }

    @Test func slateNotEditableWhenLockedEvenIfDeadlineIsFuture() {
        let deadline = Date().addingTimeInterval(7 * 24 * 3600)
        #expect(!WeekTransition.isSlateEditable(week(status: .locked, deadline: deadline)))
        #expect(!WeekTransition.isSlateEditable(week(status: .scored, deadline: deadline)))
        #expect(!WeekTransition.arePicksEditable(week(status: .locked, deadline: deadline)))
        #expect(!WeekTransition.arePicksEditable(week(status: .scored, deadline: deadline)))
    }

    @Test func picksEditableDuringPickingBeforeDeadline() {
        let deadline = Date().addingTimeInterval(7 * 24 * 3600)
        #expect(WeekTransition.arePicksEditable(week(status: .picking, deadline: deadline)))
        #expect(!WeekTransition.arePicksEditable(week(status: .selection, deadline: deadline)))
    }

    @Test func picksNotEditableAfterPickDeadline() {
        let deadline = Date().addingTimeInterval(-60)
        #expect(!WeekTransition.arePicksEditable(week(status: .picking, deadline: deadline)))
    }

    @Test func fillingSlateSetsDeadlineWithoutLockedAt() {
        let kickoff = Date().addingTimeInterval(21 * 24 * 3600)
        let updates = WeekTransition.toPickingUpdates(
            rules: .default,
            kickoffs: [kickoff],
            nominationCount: 5,
            setDeadline: true,
            lockSlate: false
        )
        #expect(updates["status"] as? String == WeekStatus.picking.rawValue)
        #expect(updates["pickDeadline"] != nil)
        #expect(updates["lockedAt"] == nil)
    }

    @Test func earlyLockSetsLockedAtAndDeadline() {
        let kickoff = Date().addingTimeInterval(21 * 24 * 3600)
        let updates = WeekTransition.lockEarlyUpdates(rules: .default, kickoffs: [kickoff])
        #expect(updates["lockedAt"] != nil)
        #expect(updates["pickDeadline"] != nil)
        #expect(updates["status"] as? String == WeekStatus.picking.rawValue)
    }
}
