import Foundation
import Testing
@testable import Pickems

struct PicksDisplayedWeekTests {
    @Test func selectionsKeepsPinnedFutureWeek() {
        let week0 = week(id: "2026-W0", number: 0)
        let week1 = week(id: "2026-W1", number: 1)
        let shown = PicksDisplayedWeek.resolve(
            current: week1,
            hideFuture: false,
            available: [week0, week1],
            activeWeekId: "2026-W0",
            isFuture: { $0.weekNumber > 0 }
        )
        #expect(shown?.id == "2026-W1")
    }

    @Test func pickemsSubstitutesActiveWeekForFuturePin() {
        let week0 = week(id: "2026-W0", number: 0)
        let week1 = week(id: "2026-W1", number: 1)
        let shown = PicksDisplayedWeek.resolve(
            current: week1,
            hideFuture: true,
            available: [week0, week1],
            activeWeekId: "2026-W0",
            isFuture: { $0.weekNumber > 0 }
        )
        #expect(shown?.id == "2026-W0")
    }

    @Test func pickemsFallsBackToLastNonFutureWhenActiveMissing() {
        let week0 = week(id: "2026-W0", number: 0)
        let week1 = week(id: "2026-W1", number: 1)
        let shown = PicksDisplayedWeek.resolve(
            current: week1,
            hideFuture: true,
            available: [week0, week1],
            activeWeekId: nil,
            isFuture: { $0.weekNumber > 0 }
        )
        #expect(shown?.id == "2026-W0")
    }

    private func week(id: String, number: Int) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: 2026,
            weekNumber: number,
            status: number == 0 ? .picking : .selection,
            slateSize: 8,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0
        )
    }
}
