import Foundation
import Testing
@testable import Pickems

struct HomeCTATests {
    private func week(
        status: WeekStatus,
        mode: SelectionMode = .member,
        selectionsPerMember: Int = 1
    ) -> WeekSummary {
        WeekSummary(
            id: "2026-W1",
            seasonYear: 2026,
            weekNumber: 1,
            status: status,
            slateSize: 4,
            selectionMode: mode,
            selectionsPerMember: selectionsPerMember,
            pickDeadline: Date().addingTimeInterval(3600),
            nominationCount: 0
        )
    }

    @Test func selectionPhaseRoutesToSelectionsTab() {
        let cta = HomeCTAResolver.resolve(
            week: week(status: .selection),
            isCommissioner: false,
            didSubmitNominations: false,
            userNominationCount: 0,
            pickCount: 0,
            slateCount: 0,
            pickemsLocked: false,
            picksSubmitted: false
        )
        #expect(cta == .makeSelections)
        #expect(cta.title == "Make Selections")
        #expect(cta.destinationTab == .selections)
    }

    @Test func commissionerBuiltSlateWaitsForMembers() {
        let cta = HomeCTAResolver.resolve(
            week: week(status: .selection, mode: .commissioner),
            isCommissioner: false,
            didSubmitNominations: false,
            userNominationCount: 0,
            pickCount: 0,
            slateCount: 0,
            pickemsLocked: false,
            picksSubmitted: false
        )
        #expect(cta == .waitingOnSelections)
        #expect(cta.destinationTab == nil)
    }

    @Test func pickingPhaseNeverSaysMakeSelections() {
        let cta = HomeCTAResolver.resolve(
            week: week(status: .picking),
            isCommissioner: false,
            didSubmitNominations: true,
            userNominationCount: 1,
            pickCount: 0,
            slateCount: 4,
            pickemsLocked: false,
            picksSubmitted: false
        )
        #expect(cta == .makePickems)
        #expect(cta.destinationTab == .pickems)
        #expect(cta.title == "Make Pickems")
    }

    @Test func submittedSelectionsUseEdit() {
        let cta = HomeCTAResolver.resolve(
            week: week(status: .selection),
            isCommissioner: false,
            didSubmitNominations: true,
            userNominationCount: 1,
            pickCount: 0,
            slateCount: 0,
            pickemsLocked: false,
            picksSubmitted: false
        )
        #expect(cta == .editSelections)
    }

    @Test func fixedSlateNeverSaysMakeSelections() {
        var fixed = week(status: .selection)
        fixed.weekNumber = 0
        fixed.slateSource = CFBWeekCalendar.weekZeroSlateSource
        let cta = HomeCTAResolver.resolve(
            week: fixed,
            isCommissioner: false,
            didSubmitNominations: false,
            userNominationCount: 0,
            pickCount: 0,
            slateCount: 8,
            pickemsLocked: false,
            picksSubmitted: false
        )
        #expect(cta == .makePickems)
        #expect(cta.destinationTab == .pickems)
    }
}
