import Foundation
import Testing
@testable import Pickems

struct StandingBoardTests {
    @Test func appendsMembersMissingFromStandings() {
        let standings = [
            entry("a", "Alex", weeklyWins: 4, weeklyLosses: 1, seasonWins: 10, seasonLosses: 5)
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

    @Test func dropsStandingsEntriesWhoAreNotMembers() {
        let standings = [
            entry("a", "Alex", weeklyWins: 4, weeklyLosses: 4, seasonWins: 4, seasonLosses: 4),
            entry("jack", "JBanda", weeklyWins: 0, weeklyLosses: 0, seasonWins: 4, seasonLosses: 4),
        ]
        let members = [member("a", "Alex", seasonWins: 4, seasonLosses: 4)]
        let merged = StandingBoard.baseEntries(standingsEntries: standings, members: members)
        #expect(merged.map(\.id) == ["a"])
    }

    @Test func rosterDropsMembersNotInMemberIds() {
        let members = [
            member("a", "Alex"),
            member("jack", "JBanda", seasonWins: 4, seasonLosses: 4),
        ]
        let roster = StandingBoard.roster(members: members, memberIds: ["a"])
        #expect(roster.map(\.id) == ["a"])
    }

    @Test func emptyMembersFallsBackToStandingsIntersectingMemberIds() {
        let standings = [
            entry("a", "Alex", weeklyWins: 6, weeklyLosses: 2, seasonWins: 6, seasonLosses: 2),
            entry("jack", "JBanda", weeklyWins: 0, weeklyLosses: 0, seasonWins: 4, seasonLosses: 4),
        ]
        let merged = StandingBoard.baseEntries(
            standingsEntries: standings,
            members: [],
            memberIds: ["a"]
        )
        #expect(merged.map(\.id) == ["a"])
    }

    @Test func widgetRankingDropsOtherLeagueMember() {
        let standings = GroupStandings(
            groupId: "ppp",
            weekNumber: 0,
            entries: [
                entry("a", "Alex", weeklyWins: 6, weeklyLosses: 2, seasonWins: 6, seasonLosses: 2),
                entry("you", "Fannypack", weeklyWins: 4, weeklyLosses: 4, seasonWins: 4, seasonLosses: 4),
            ],
            updatedAt: Date()
        )
        let otherLeagueMembers = [
            member("a", "Alex", seasonWins: 6, seasonLosses: 2),
            member("you", "Fannypack", seasonWins: 4, seasonLosses: 4),
            member("jack", "JBanda", seasonWins: 4, seasonLosses: 4),
        ]
        let ranked = WidgetSnapshotService.rankedDisplayEntries(
            standings: standings,
            members: otherLeagueMembers,
            memberIds: ["a", "you"],
            tieBreaker: .commissionerOverride
        )
        #expect(ranked.map(\.id) == ["a", "you"])
        #expect(!ranked.contains(where: { $0.id == "jack" }))
    }

    private func entry(
        _ id: String,
        _ name: String,
        weeklyWins: Int,
        weeklyLosses: Int,
        seasonWins: Int,
        seasonLosses: Int
    ) -> StandingEntry {
        StandingEntry(
            id: id,
            displayName: name,
            avatarColorHex: "#111",
            weeklyWins: weeklyWins,
            weeklyLosses: weeklyLosses,
            seasonWins: seasonWins,
            seasonLosses: seasonLosses,
            rank: 0,
            isTied: false
        )
    }

    private func member(
        _ id: String,
        _ name: String,
        seasonWins: Int = 0,
        seasonLosses: Int = 0
    ) -> GroupMember {
        GroupMember(
            id: id,
            displayName: name,
            avatarColorHex: "#111",
            role: .member,
            joinedAt: Date(),
            seasonWins: seasonWins,
            seasonLosses: seasonLosses
        )
    }
}
