import Foundation
import Testing
@testable import Pickems

struct CommissionerAdminSummaryTests {
    private func nomination(_ userId: String, _ event: String) -> Nomination {
        Nomination(
            id: "\(userId)-\(event)",
            submittedBy: userId,
            submitterName: userId,
            espnEventId: event,
            spread: 3.5,
            spreadTeamId: "home",
            homeTeamId: "home",
            homeTeamName: "Home",
            awayTeamId: "away",
            awayTeamName: "Away",
            kickoff: Date(timeIntervalSince1970: 1_800_000_000),
            createdAt: Date(timeIntervalSince1970: 1_799_000_000)
        )
    }

    @Test func selectionsCountsMembersWhoFinished() {
        let noms = [
            nomination("a", "1"), nomination("a", "2"),
            nomination("b", "3"),
        ]
        let summary = CommissionerAdminSummary.selections(memberIds: ["a", "b", "c"], nominations: noms, perMember: 2)
        #expect(summary == "1/3 in")
    }

    @Test func selectionsWithNoMembers() {
        #expect(CommissionerAdminSummary.selections(memberIds: [], nominations: [], perMember: 2) == "0/0 in")
    }

    @Test func slateAndMembersCopy() {
        #expect(CommissionerAdminSummary.slate(gameCount: 12) == "12 games")
        #expect(CommissionerAdminSummary.slate(gameCount: 1) == "1 game")
        #expect(CommissionerAdminSummary.members(count: 12) == "12")
    }
}
