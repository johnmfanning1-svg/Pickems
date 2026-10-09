import Foundation
import Testing
@testable import Pickems

struct SelectionDeadlineDisplayTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func openWithDeadlineCountsDown() {
        let due = now.addingTimeInterval(2 * 3600)
        let week = week(status: .selection, selectionDeadline: due)
        let state = SelectionDeadlineDisplayResolver.resolve(week: week, now: now)

        #expect(!WeekTransition.showsSelectionsLockedBanner(week))
        #expect(state == .open(deadline: due))
        #expect(state?.isCountingDown == true)
        #expect(CommissionerAdminSummary.selectionDeadlineSummary(week: week, now: now)
            == PickDeadlineCalculator.lockTimeLabel(for: due))

        let snapshot = WorkspaceDeadlineDisplay.snapshot(
            kind: .selections,
            week: week,
            isCommissioner: true,
            games: [],
            now: now
        )
        #expect(snapshot.selectionState == .open(deadline: due))
        #expect(snapshot.clockIsLive)
        #expect(!snapshot.showSetSelectionDeadlinePrompt)
        #expect(!snapshot.isPromptingCommissioner(for: .selections))
    }

    @Test func openWithoutDeadlinePromptsCommissionerOnly() {
        let week = week(status: .selection)
        let state = SelectionDeadlineDisplayResolver.resolve(week: week, now: now)

        #expect(state == .needsDeadline)
        #expect(state?.isCountingDown == false)
        #expect(CommissionerAdminSummary.selectionDeadlineSummary(week: week, now: now) == nil)
        #expect(WorkspaceDeadlineDisplay.commissionerPrompt(
            kind: .selections,
            week: week,
            isCommissioner: true,
            now: now
        ) == .selections)
        #expect(WorkspaceDeadlineDisplay.commissionerPrompt(
            kind: .selections,
            week: week,
            isCommissioner: false,
            now: now
        ) == nil)

        let member = WorkspaceDeadlineDisplay.snapshot(
            kind: .selections,
            week: week,
            isCommissioner: false,
            games: [],
            now: now
        )
        #expect(!member.showSetSelectionDeadlinePrompt)
        #expect(!member.hasContent)
    }

    @Test func fullSlateBeforeDeadlineIsStaticLock() {
        let due = now.addingTimeInterval(2 * 3600)
        let pickLock = now.addingTimeInterval(26 * 3600)
        let week = week(status: .picking, selectionDeadline: due, pickDeadline: pickLock)

        #expect(WeekTransition.showsSelectionsLockedBanner(week))
        #expect(WeekTransition.arePickemsOpen(week))
        let state = SelectionDeadlineDisplayResolver.resolve(week: week, now: now)
        #expect(state == .locked(SelectionLockCopy(title: "Locked", detail: "Locked when slate filled")))
        #expect(state?.isCountingDown == false)

        let summary = CommissionerAdminSummary.selectionDeadlineSummary(week: week, now: now)
        let countdown = PickDeadlineCalculator.countdownLabel(to: due, now: now)
        #expect(countdown.contains("left"))
        #expect(summary == "Locked when slate filled")
        #expect(summary != countdown)
        #expect(summary?.contains("left") == false)

        let snapshot = WorkspaceDeadlineDisplay.snapshot(
            kind: .selections,
            week: week,
            isCommissioner: true,
            games: [],
            now: now
        )
        #expect(snapshot.selectionDeadline == due)
        #expect(snapshot.pickemsDeadline == pickLock)
        #expect(snapshot.selectionState?.isCountingDown == false)
        #expect(!snapshot.showSetSelectionDeadlinePrompt)
        #expect(!snapshot.isPromptingCommissioner(for: .selections))
        #expect(snapshot.clockIsLive)
    }

    @Test func passedDeadlineIsStaticClosed() {
        let due = now.addingTimeInterval(-60)
        let week = week(status: .selection, selectionDeadline: due)
        let closed = "Closed \(PickDeadlineCalculator.lockTimeLabel(for: due))"

        #expect(!WeekTransition.showsSelectionsLockedBanner(week))
        #expect(SelectionDeadlineDisplayResolver.isClosed(week, now: now))
        let state = SelectionDeadlineDisplayResolver.resolve(week: week, now: now)
        #expect(state == .locked(SelectionLockCopy(title: "Locked", detail: closed)))
        #expect(state?.isCountingDown == false)
        #expect(WorkspaceDeadlineDisplay.commissionerPrompt(
            kind: .selections,
            week: week,
            isCommissioner: true,
            now: now
        ) == nil)
        #expect(CommissionerAdminSummary.selectionDeadlineSummary(week: week, now: now) == closed)
    }

    @Test func pickemsOpenStopsSelectionCountdown() {
        let due = now.addingTimeInterval(90 * 60)
        let week = week(status: .picking, selectionDeadline: due)

        #expect(WeekTransition.arePickemsOpen(week))
        #expect(WeekTransition.showsSelectionsLockedBanner(week))
        let state = SelectionDeadlineDisplayResolver.resolve(week: week, now: now)
        #expect(state?.isCountingDown == false)
        guard case .locked(let copy) = state else {
            Issue.record("Pickems opening must lock the Selections row")
            return
        }
        #expect(copy.title == "Locked")
        #expect(copy.compact.contains("left") == false)

        let snapshot = WorkspaceDeadlineDisplay.snapshot(
            kind: .selections,
            week: week,
            isCommissioner: false,
            games: [],
            now: now
        )
        #expect(snapshot.hasContent)
        #expect(snapshot.pickemsDeadline == nil)
        #expect(!snapshot.clockIsLive)
        #expect(!snapshot.showSetSelectionDeadlinePrompt)
    }

    @Test func bannerAndRowNeverDisagree() {
        let future = now.addingTimeInterval(3 * 3600)
        let past = now.addingTimeInterval(-3600)
        let samples = [
            week(status: .picking, selectionDeadline: future),
            week(status: .picking, selectionDeadline: past),
            week(status: .picking, selectionDeadline: nil, lockedAt: past),
            week(status: .locked, selectionDeadline: future),
            week(status: .scored, selectionDeadline: past),
            week(status: .scored, selectionDeadline: nil),
        ]
        for sample in samples {
            #expect(WeekTransition.showsSelectionsLockedBanner(sample))
            let state = SelectionDeadlineDisplayResolver.resolve(week: sample, now: now)
            #expect(SelectionDeadlineDisplayResolver.isClosed(sample, now: now))
            #expect(state?.isCountingDown == false)
            if case .locked(let copy) = state {
                #expect(copy.title == "Locked")
                #expect(copy.compact.contains("left") == false)
            } else {
                Issue.record("lock banner requires a static Selections row")
            }
        }
    }

    @Test func commissionerLockAndInProgressWeeksStayStatic() {
        let due = now.addingTimeInterval(4 * 3600)
        let commissioner = week(
            status: .picking,
            selectionDeadline: due,
            lockedAt: now.addingTimeInterval(-30)
        )
        #expect(SelectionDeadlineDisplayResolver.resolve(week: commissioner, now: now)
            == .locked(SelectionLockCopy(title: "Locked", detail: nil)))

        for status in [WeekStatus.locked, .scored] {
            let progressed = week(status: status, selectionDeadline: due)
            let state = SelectionDeadlineDisplayResolver.resolve(week: progressed, now: now)
            #expect(state == .locked(SelectionLockCopy(title: "Locked", detail: nil)))
            #expect(state?.isCountingDown == false)
        }
    }

    @Test func weekZeroHasNoSelectionRow() {
        let week = week(
            status: .picking,
            weekNumber: 0,
            selectionDeadline: now.addingTimeInterval(3600),
            slateSource: CFBWeekCalendar.weekZeroSlateSource
        )
        #expect(week.skipsSelection)
        #expect(!WeekTransition.showsSelectionsLockedBanner(week))
        #expect(SelectionDeadlineDisplayResolver.resolve(week: week, now: now) == nil)
    }

    private func week(
        status: WeekStatus,
        weekNumber: Int = 6,
        selectionDeadline: Date? = nil,
        pickDeadline: Date? = nil,
        lockedAt: Date? = nil,
        slateSource: String? = nil
    ) -> WeekSummary {
        WeekSummary(
            id: "2026-W\(weekNumber)",
            seasonYear: 2026,
            weekNumber: weekNumber,
            status: status,
            slateSize: 12,
            selectionMode: .member,
            selectionsPerMember: 3,
            lockedAt: lockedAt,
            pickDeadline: pickDeadline,
            nominationCount: 12,
            selectionDeadline: selectionDeadline,
            slateSource: slateSource
        )
    }
}
