import Foundation
import Testing
@testable import Pickems

struct StandingBoardTests {
    @Test func appendsMembersMissingFromStandings() {
        let standings = [
            StandingEntry(
                id: "a",
                displayName: "Alex",
                avatarColorHex: "#111",
                weeklyWins: 4,
                weeklyLosses: 1,
                seasonWins: 10,
                seasonLosses: 5,
                rank: 1,
                isTied: false
            )
        ]
        let members = [member("a", "Alex"), member("b", "Blake")]
        let merged = StandingBoard.baseEntries(standingsEntries: standings, members: members)
        #expect(merged.map(\.id) == ["a", "b"])
        #expect(merged.first?.weeklyWins == 4)
        #expect(merged.last?.weeklyWins == 0)
        #expect(merged.last?.displayName == "Blake")
    }

    @Test func usesRosterWhenStandingsAreEmpty() {
        let members = [member("a", "Alex"), member("b", "Blake")]
        let merged = StandingBoard.baseEntries(standingsEntries: [], members: members)
        #expect(merged.map(\.id) == ["a", "b"])
    }

    private func member(_ id: String, _ name: String) -> GroupMember {
        GroupMember(
            id: id,
            displayName: name,
            avatarColorHex: "#111",
            role: .member,
            joinedAt: Date(),
            seasonWins: 0,
            seasonLosses: 0
        )
    }
}
