import Foundation
import Testing
@testable import Pickems

struct WidgetDeepLinkTests {
    @Test func gameAndLeaderboardRowLinks() throws {
        let snapshot = StandingsSnapshot(
            groupId: "league-1",
            groupName: "Saturday Crew",
            weekNumber: 6,
            seasonYear: 2026,
            userId: "u",
            userDisplayName: "You",
            weeklyWins: 4,
            weeklyLosses: 1,
            seasonWins: 20,
            seasonLosses: 8,
            rank: 2,
            totalPlayers: 8,
            topEntries: [],
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let game = try #require(WidgetDeepLink.gameURL(snapshot: snapshot, gameId: "game-osu"))
        let board = try #require(WidgetDeepLink.leaderboardURL(snapshot: snapshot))
        #expect(DeepLinkRouter.parse(url: game) == .openGame(groupId: "league-1", weekId: "2026-W6", gameId: "game-osu"))
        #expect(DeepLinkRouter.parse(url: board) == .openLeaderboard(groupId: "league-1", weekId: "2026-W6"))
        #expect(WidgetDeepLink.gameURL(snapshot: snapshot, gameId: "") == nil)
    }

    @Test func gamePathFallsBackToThePickemsList() throws {
        let missing = try #require(URL(string: "pickems://league/league-1/week/2026-W6/game"))
        #expect(DeepLinkRouter.parse(url: missing) == .openWeekPickems(groupId: "league-1", weekId: "2026-W6"))
        let present = try #require(URL(string: "pickems://league/league-1/week/2026-W6/game/game-osu"))
        #expect(DeepLinkRouter.parse(url: present) == .openGame(groupId: "league-1", weekId: "2026-W6", gameId: "game-osu"))
    }
}
