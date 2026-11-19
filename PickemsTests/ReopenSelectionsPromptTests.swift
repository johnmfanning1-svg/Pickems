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

    @Test func confirmWriteTargetRequiresSameLiveWeekId() {
        let picking = week(status: .picking)
        let target = ReopenSelectionsPrompt.confirmWriteTarget(
            settingsGroupId: "league-a",
            pinnedWeekId: "2026-W12",
            liveWeek: picking
        )
        #expect(target?.groupId == "league-a")
        #expect(target?.weekId == "2026-W12")

        #expect(ReopenSelectionsPrompt.confirmWriteTarget(
            settingsGroupId: "league-a",
            pinnedWeekId: "2026-W12",
            liveWeek: week(status: .selection)
        ) == nil)
        #expect(ReopenSelectionsPrompt.confirmWriteTarget(
            settingsGroupId: "league-a",
            pinnedWeekId: "2026-W11",
            liveWeek: picking
        ) == nil)
        #expect(ReopenSelectionsPrompt.confirmWriteTarget(
            settingsGroupId: "league-a",
            pinnedWeekId: "2026-W12",
            liveWeek: nil
        ) == nil)
    }

    @Test func captureForReopenDeadlinePinsLeague() throws {
        let week = week(status: .locked)
        let capture = try #require(ReopenSelectionsPrompt.captureForReopenDeadline(
            settingsGroupId: "league-a",
            week: week
        ))
        #expect(capture.groupId == "league-a")
        #expect(capture.weekId == "2026-W12")
        #expect(capture.weekLabel == week.displayLabel)
    }

    @Test func defaultReopenDeadlineIsInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let deadline = ReopenSelectionsPrompt.defaultReopenDeadline(now: now)
        #expect(deadline > now)
    }
}