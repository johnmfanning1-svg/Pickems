import Foundation
import FirebaseFirestore
import Testing
@testable import Pickems

struct WeekTransitionTests {
    private func week(
        status: WeekStatus,
        deadline: Date? = nil,
        lockedAt: Date? = nil,
        selectionDeadline: Date? = nil,
        pickLockMode: DeadlinePolicy? = nil,
        weekLockAt: Date? = nil
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
            pickLockMode: pickLockMode,
            weekLockAt: weekLockAt,
            nominationCount: 5,
            selectionDeadline: selectionDeadline
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

    @Test func pickemsBoardShowsWhenLockedOrScored() {
        #expect(WeekTransition.pickemsShouldShowLeagueBoard(week(status: .locked)))
        #expect(WeekTransition.pickemsShouldShowLeagueBoard(week(status: .scored)))
    }

    @Test func pickemsBoardShowsWhenPickingAfterDeadline() {
        let past = Date().addingTimeInterval(-60)
        #expect(WeekTransition.pickemsShouldShowLeagueBoard(week(status: .picking, deadline: past)))
        #expect(!WeekTransition.arePicksEditable(week(status: .picking, deadline: past)))
    }

    @Test func pickemsBoardHiddenWhilePickingBeforeDeadline() {
        let future = Date().addingTimeInterval(7 * 24 * 3600)
        #expect(!WeekTransition.pickemsShouldShowLeagueBoard(week(status: .picking, deadline: future)))
        #expect(!WeekTransition.pickemsShouldShowLeagueBoard(week(status: .picking)))
        #expect(!WeekTransition.pickemsShouldShowLeagueBoard(week(status: .selection)))
    }

    @Test func fillingSlateDoesNotAutoOpenPicking() {
        #expect(!WeekTransition.opensPickingWhenSlateFills)
    }

    @Test func remakeSelectionsAllowedDuringSelectionBeforeDeadline() {
        let future = Date().addingTimeInterval(7 * 24 * 3600)
        #expect(WeekTransition.canRemakeSelections(week(status: .selection, selectionDeadline: future)))
        #expect(WeekTransition.canRemakeSelections(week(status: .selection)))
        #expect(WeekTransition.isSlateEditable(week(status: .selection, selectionDeadline: future)))
    }

    @Test func remakeSelectionsBlockedAfterDeadlineOrPicking() {
        let past = Date().addingTimeInterval(-60)
        #expect(!WeekTransition.canRemakeSelections(week(status: .selection, selectionDeadline: past)))
        #expect(!WeekTransition.canRemakeSelections(week(status: .picking)))
        #expect(!WeekTransition.arePickemsOpen(week(status: .selection)))
        #expect(WeekTransition.arePickemsOpen(week(status: .picking)))
        #expect(!WeekTransition.arePicksEditable(week(status: .selection)))
    }

    @Test func reopenSelectionsAllowedWhilePickingOrLocked() {
        #expect(WeekTransition.canReopenSelections(week(status: .picking)))
        #expect(WeekTransition.canReopenSelections(week(status: .locked)))
        #expect(!WeekTransition.canReopenSelections(week(status: .selection)))
        #expect(!WeekTransition.canReopenSelections(week(status: .scored)))
    }

    @Test func fixedSlateCannotReopenOrRemakeSelections() {
        var fixed = week(status: .picking)
        fixed.weekNumber = 0
        fixed.id = "2026-W0"
        fixed.slateSource = CFBWeekCalendar.weekZeroSlateSource
        #expect(fixed.skipsSelection)
        #expect(!WeekTransition.canReopenSelections(fixed))
        #expect(!WeekTransition.canRemakeSelections(fixed))
        #expect(WeekTransition.arePickemsOpen(fixed))
    }

    @Test func toSelectionUpdatesClearsLockAndSetsSelection() {
        let updates = WeekTransition.toSelectionUpdates()
        #expect(updates["status"] as? String == WeekStatus.selection.rawValue)
        #expect(updates["lockedAt"] != nil)
    }

    @Test func remakeSelectionsWorksAfterReopenClearsDeadline() {
        #expect(WeekTransition.canRemakeSelections(week(status: .selection)))
        #expect(!WeekTransition.arePickemsOpen(week(status: .selection)))
    }

    @Test func commissionerCanManageSelectionsDuringSelectionEvenAfterDeadline() {
        let past = Date().addingTimeInterval(-60)
        #expect(WeekTransition.commissionerCanManageSelections(week(status: .selection)))
        #expect(WeekTransition.commissionerCanManageSelections(
            week(status: .selection, selectionDeadline: past)
        ))
        #expect(!WeekTransition.canRemakeSelections(
            week(status: .selection, selectionDeadline: past)
        ))
        #expect(!WeekTransition.commissionerCanManageSelections(week(status: .picking)))
        #expect(!WeekTransition.commissionerCanManageSelections(week(status: .scored)))
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
        #expect(updates["pickLockMode"] as? String == DeadlinePolicy.firstKickoff.rawValue)
        #expect(updates["lockedAt"] == nil)
    }

    @Test func rollingSnapshotUsesLastKickoffForWeekLock() {
        let first = Date().addingTimeInterval(3600)
        let last = Date().addingTimeInterval(7200)
        var rules = GroupRules.default
        rules.pickDeadline = .rolling
        let updates = WeekTransition.toPickingUpdates(
            rules: rules,
            games: [("thu", first), ("sun", last)],
            setDeadline: true,
            lockSlate: false
        )
        #expect(updates["pickLockMode"] as? String == DeadlinePolicy.rolling.rawValue)
        let deadline = (updates["pickDeadline"] as? Timestamp)?.dateValue()
        let weekLock = (updates["weekLockAt"] as? Timestamp)?.dateValue()
        #expect(deadline == first)
        #expect(weekLock == last)
        #expect(updates["gameIds"] as? [String] == ["thu", "sun"])
    }

    @Test func rollingKeepsPicksEditableAfterFirstKickoff() {
        let first = Date().addingTimeInterval(-60)
        let last = Date().addingTimeInterval(3600)
        let rolling = week(
            status: .picking,
            deadline: first,
            pickLockMode: .rolling,
            weekLockAt: last
        )
        #expect(WeekTransition.arePicksEditable(rolling))
        #expect(!WeekTransition.arePicksFullyLocked(rolling))
        #expect(WeekTransition.pickemsShouldShowLeagueBoard(rolling))
        #expect(!WeekTransition.pickemsShouldShowFullLockedPhase(rolling))
        #expect(!WeekTransition.pickemsAreFullyPublic(rolling))
        #expect(WeekTransition.isGameLocked(
            gameId: "thu",
            kickoff: first,
            week: rolling
        ))
        #expect(!WeekTransition.isGameLocked(
            gameId: "sun",
            kickoff: last,
            week: rolling
        ))
    }

    @Test func rollingFullyLocksAtLastKickoff() {
        let first = Date().addingTimeInterval(-3600)
        let last = Date().addingTimeInterval(-60)
        let rolling = week(
            status: .picking,
            deadline: first,
            pickLockMode: .rolling,
            weekLockAt: last
        )
        #expect(!WeekTransition.arePicksEditable(rolling))
        #expect(WeekTransition.arePicksFullyLocked(rolling))
        #expect(WeekTransition.pickemsShouldShowFullLockedPhase(rolling))
        #expect(WeekTransition.pickemsAreFullyPublic(rolling))
    }

    @Test func remainingLockAtFreezesOpenRollingGamesWithoutMovingWeekLock() {
        let first = Date().addingTimeInterval(-60)
        let last = Date().addingTimeInterval(3600)
        var rolling = week(
            status: .picking,
            deadline: first,
            pickLockMode: .rolling,
            weekLockAt: last
        )
        rolling.remainingLockAt = Date().addingTimeInterval(-1)
        #expect(WeekTransition.arePicksFullyLocked(rolling))
        #expect(WeekTransition.isGameLocked(gameId: "sun", kickoff: last, week: rolling))
        #expect(rolling.weekLockAt == last)
    }

    @Test func earlyLockSetsLockedAtAndDeadline() {
        let kickoff = Date().addingTimeInterval(21 * 24 * 3600)
        let updates = WeekTransition.lockEarlyUpdates(rules: .default, kickoffs: [kickoff])
        #expect(updates["lockedAt"] != nil)
        #expect(updates["pickDeadline"] != nil)
        #expect(updates["status"] as? String == WeekStatus.picking.rawValue)
    }
}
