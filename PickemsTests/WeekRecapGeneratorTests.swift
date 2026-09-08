import Foundation
import Testing
@testable import Pickems

struct WeekRecapGeneratorTests {
    @Test func scoredRecapNamesLeaderAndYourWeek() {
        let text = WeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .scored),
            entries: [
                entry(id: "a", name: "Ace", wins: 8, losses: 2, rank: 1),
                entry(id: "u1", name: "JMF", wins: 4, losses: 7, rank: 2)
            ],
            userId: "u1"
        )
        #expect(text.contains("Core 4 OG — Week 1 Recap"))
        #expect(text.contains("Leader: Ace (8–2)"))
        #expect(text.contains("Your week: 4–7 against the spread"))
        #expect(!text.contains("4/7"))
    }

    @Test func inProgressRecapIncludesYourRecordSoFar() {
        let text = WeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .locked),
            entries: [
                entry(id: "u1", name: "JMF", wins: 2, losses: 1, rank: 1)
            ],
            userId: "u1"
        )
        #expect(text.contains("Week 1 is still in progress."))
        #expect(text.contains("Your week so far: 2–1 against the spread"))
        #expect(!text.contains("Recap"))
    }

    @Test func inProgressWithoutResultsStaysShort() {
        let text = WeekRecapGenerator.recap(
            groupName: "Core 4 OG",
            week: week(status: .selection),
            entries: [
                entry(id: "u1", name: "JMF", wins: 0, losses: 0, rank: 1)
            ],
            userId: "u1"
        )
        #expect(text == "Week 1 is still in progress.")
    }

    private func week(status: WeekStatus) -> WeekSummary {
        WeekSummary(
            id: "2026-W1",
            seasonYear: 2026,
            weekNumber: 1,
            status: status,
            slateSize: 11,
            selectionMode: .member,
            selectionsPerMember: 1,
            nominationCount: 0
        )
    }

    private func entry(id: String, name: String, wins: Int, losses: Int, rank: Int) -> StandingEntry {
        StandingEntry(
            id: id,
            displayName: name,
            avatarColorHex: "#DC2626",
            weeklyWins: wins,
            weeklyLosses: losses,
            seasonWins: wins,
            seasonLosses: losses,
            rank: rank,
            isTied: false
        )
    }
}
