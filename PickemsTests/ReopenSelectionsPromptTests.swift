import Foundation
import Testing
@testable import Pickems

struct ReopenSelectionsPromptTests {
    private func week(status: WeekStatus) -> WeekSummary {
        WeekSummary(
            id: "2026-W12",
            seasonYear: 2026,
            weekNumber: 12,
            status: status,
            slateSize: 5,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 5,
            selectionDeadline: nil
        )
    }

    @Test func writeTargetUsesPinnedLeagueAndWeek() {
        let week = week(status: .picking)
        let target = ReopenSelectionsPrompt.writeTarget(settingsGroupId: "league-a", week: week)
        #expect(target?.groupId == "league-a")
        #expect(target?.weekId == "2026-W12")
    }

    @Test func writeTargetNilWhenWeekCannotReopen() {
        #expect(ReopenSelectionsPrompt.writeTarget(settingsGroupId: "league-a", week: week(status: .selection)) == nil)
        #expect(ReopenSelectionsPrompt.writeTarget(settingsGroupId: "league-a", week: week(status: .scored)) == nil)
    }
}