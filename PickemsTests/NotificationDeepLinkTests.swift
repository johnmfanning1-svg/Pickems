import Foundation
import Testing
@testable import Pickems

struct NotificationDeepLinkTests {
    private let groupId = "group-1"
    private let weekId = "2026-W6"
    private let gameId = "game-osu"

    @Test func gameFinalPayloadOpensThatGame() {
        let action = DeepLinkRouter.parseNotification(userInfo: [
            "type": "game_final",
            "groupId": groupId,
            "weekId": weekId,
            "gameId": gameId,
            "deepLink": "pickems://league/group-1/week/2026-W6/game/game-osu",
            "result": "covered",
        ])
        #expect(action == .openGame(groupId: groupId, weekId: weekId, gameId: gameId))
        #expect(
            NotificationLaunch.resolve(
                action: action!,
                groupsLoaded: true,
                memberGroupIds: [groupId]
            ) == .pickems(groupId: groupId, weekId: weekId, gameId: gameId)
        )
    }

    @Test func singleNoPickPayloadOpensThatGame() {
        let action = DeepLinkRouter.parseNotification(userInfo: [
            "type": "no_pick",
            "groupId": groupId,
            "weekId": weekId,
            "gameId": gameId,
            "deepLink": "pickems://league/group-1/week/2026-W6/game/game-osu",
        ])
        #expect(action == .openGame(groupId: groupId, weekId: weekId, gameId: gameId))
    }

    @Test func combinedNoPickPayloadOpensWeekPickems() {
        let action = DeepLinkRouter.parseNotification(userInfo: [
            "type": "no_pick",
            "groupId": groupId,
            "weekId": weekId,
            "deepLink": "pickems://league/group-1/week/2026-W6/pickems",
            "gameCount": "3",
        ])
        #expect(action == .openWeekPickems(groupId: groupId, weekId: weekId))
        #expect(
            NotificationLaunch.resolve(
                action: action!,
                groupsLoaded: true,
                memberGroupIds: [groupId, "other"]
            ) == .pickems(groupId: groupId, weekId: weekId, gameId: nil)
        )
    }

    @Test func leadPayloadOpensThisWeekLeaderboard() {
        let action = DeepLinkRouter.parseNotification(userInfo: [
            "type": "lead",
            "groupId": groupId,
            "weekId": weekId,
            "deepLink": "pickems://league/group-1/week/2026-W6/leaderboard",
        ])
        #expect(action == .openLeaderboard(groupId: groupId, weekId: weekId))
        #expect(
            NotificationLaunch.resolve(
                action: action!,
                groupsLoaded: true,
                memberGroupIds: [groupId]
            ) == .leaderboard(groupId: groupId, weekId: weekId)
        )
        let choice = NotificationLaunch.leaderboardChoice(leagueId: groupId)
        #expect(
            LeaderboardScope.resolvedScope(
                week: week(status: .scored),
                leagueId: groupId,
                manual: choice
            ) == .thisWeek
        )
    }

    @Test func deepLinkURLRoutesThroughTheSameParser() {
        #expect(
            DeepLinkRouter.parse(url: URL(string: "pickems://league/group-1/week/2026-W6/game/game-osu")!)
                == .openGame(groupId: groupId, weekId: weekId, gameId: gameId)
        )
        #expect(
            DeepLinkRouter.parse(url: URL(string: "pickems://league/group-1/week/2026-W6/pickems")!)
                == .openWeekPickems(groupId: groupId, weekId: weekId)
        )
        #expect(
            DeepLinkRouter.parse(url: URL(string: "pickems://league/group-1/week/2026-W6/leaderboard")!)
                == .openLeaderboard(groupId: groupId, weekId: weekId)
        )
        #expect(
            DeepLinkRouter.parse(url: URL(string: "https://pickems.app/league/group-1/week/2026-W6/game/game-osu")!)
                == .openGame(groupId: groupId, weekId: weekId, gameId: gameId)
        )
    }

    @Test func deepLinkWinsWhenThePayloadAlsoHasAType() {
        let action = DeepLinkRouter.parseNotification(userInfo: [
            "type": "took_the_lead",
            "deepLink": "pickems://league/group-1/week/2026-W6/game/game-osu",
        ])
        #expect(action == .openGame(groupId: groupId, weekId: weekId, gameId: gameId))
    }

    @Test func legacyPayloadsWithoutAGameStillOpenTheLiveSlate() {
        #expect(
            DeepLinkRouter.parseNotification(userInfo: ["type": "game_final"])
                == .openLiveSlate(groupId: nil)
        )
        #expect(
            DeepLinkRouter.parseNotification(userInfo: ["type": "took_the_lead"])
                == .openLiveSlate(groupId: nil)
        )
        #expect(
            DeepLinkRouter.parseNotification(userInfo: [
                "type": "took_the_lead",
                "groupId": groupId,
                "weekId": weekId,
            ]) == .openLeaderboard(groupId: groupId, weekId: weekId)
        )
    }

    @Test func coldLaunchDefersUntilMembershipIsKnown() {
        let action = DeepLinkAction.openGame(groupId: groupId, weekId: weekId, gameId: gameId)
        #expect(
            NotificationLaunch.resolve(
                action: action,
                groupsLoaded: false,
                memberGroupIds: []
            ) == .deferred
        )
    }

    @Test func missingLeagueFallsBackHome() {
        let action = DeepLinkAction.openGame(groupId: groupId, weekId: weekId, gameId: gameId)
        #expect(
            NotificationLaunch.resolve(
                action: action,
                groupsLoaded: true,
                memberGroupIds: ["someone-else"]
            ) == .home
        )
        #expect(
            NotificationLaunch.resolve(
                action: .openLeaderboard(groupId: groupId, weekId: weekId),
                groupsLoaded: true,
                memberGroupIds: []
            ) == .home
        )
    }

    @Test func malformedPayloadDoesNotTrap() {
        #expect(DeepLinkRouter.parseNotification(userInfo: [:]) == nil)
        #expect(DeepLinkRouter.parseNotification(userInfo: ["deepLink": "not a route"]) == nil)
        #expect(DeepLinkRouter.parseNotification(userInfo: ["type": "no_pick"]) == .openPickems(groupId: nil))
        #expect(DeepLinkRouter.parse(url: URL(string: "pickems://league")!) == nil)
        #expect(DeepLinkRouter.parse(url: URL(string: "pickems://pickems")!) == .openPickems(groupId: nil))
    }

    @Test func coordinatorRolePushOpensTheLeague() {
        let action = DeepLinkRouter.parseNotification(userInfo: [
            "type": "coordinator_role",
            "groupId": groupId,
            "role": "oc",
            "change": "appointed",
        ])
        #expect(action == .openLeagues(groupId: groupId))
        #expect(
            NotificationLaunch.resolve(
                action: action!,
                groupsLoaded: true,
                memberGroupIds: [groupId]
            ) == nil
        )
    }

    @Test func gameDetailSheetIdentityFollowsTheGame() {
        #expect(AppSheet.gameDetail(gameId: "g1").id == "gameDetail.g1")
        #expect(AppSheet.gameDetail(gameId: "g1").id != AppSheet.gameDetail(gameId: "g2").id)
    }

    private func week(status: WeekStatus) -> WeekSummary {
        WeekSummary(
            id: weekId,
            seasonYear: 2026,
            weekNumber: 6,
            status: status,
            slateSize: 10,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0
        )
    }
}
