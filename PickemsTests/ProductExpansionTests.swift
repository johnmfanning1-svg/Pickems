import Foundation
import Testing
@testable import Pickems

struct ProductExpansionTests {
    @Test func confidencePickDoublesWeight() {
        let game = SlateGame(
            id: "g1",
            espnEventId: "g1",
            homeTeamId: "home",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "away",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            spread: 7,
            spreadTeamId: "home",
            kickoff: Date(),
            status: .final,
            homeScore: 28,
            awayScore: 10,
            winnerTeamId: "home"
        )
        let normal = ScoringEngine.scorePicks(picks: ["g1": "home"], games: [game])
        let confidence = ScoringEngine.scorePicks(
            picks: ["g1": "home"],
            games: [game],
            confidenceGameId: "g1"
        )
        #expect(normal.wins == 1)
        #expect(confidence.wins == 2)
    }

    @Test func rivalryHeadToHeadCountsWeeklyWinners() {
        let result = RivalryEngine.headToHead(
            userAId: "a",
            userBId: "b",
            weekResults: [
                (weekId: "1", aWins: 5, aLosses: 1, bWins: 3, bLosses: 3),
                (weekId: "2", aWins: 2, aLosses: 4, bWins: 4, bLosses: 2),
                (weekId: "3", aWins: 3, aLosses: 3, bWins: 3, bLosses: 3),
            ]
        )
        #expect(result.userAWins == 1)
        #expect(result.userBWins == 1)
        #expect(result.ties == 1)
        #expect(result.weeksCompared == 3)
    }

    @Test func streakBadgeLabels() {
        #expect(StreakEngine.badgeLabel(for: 2) == nil)
        #expect(StreakEngine.badgeLabel(for: 3) == "3-week heater")
        #expect(StreakEngine.badgeLabel(for: 5) == "Unstoppable")
        #expect(StreakEngine.isPerfectSaturday(wins: 12, losses: 0, slateSize: 12))
    }

    @Test func weekAwardsPicksSharpshooter() {
        let games = [
            makeFinal(id: "1", home: 30, away: 10),
            makeFinal(id: "2", home: 24, away: 17),
        ]
        let picks = [
            UserPick(id: "a", userId: "a", displayName: "Alex", picks: ["1": "home", "2": "home"], submittedAt: Date(), isLocked: true),
            UserPick(id: "b", userId: "b", displayName: "Blake", picks: ["1": "away", "2": "away"], submittedAt: Date(), isLocked: true),
        ]
        let members = [
            GroupMember(id: "a", displayName: "Alex", avatarColorHex: "#111", role: .member, joinedAt: Date(), seasonWins: 0, seasonLosses: 0),
            GroupMember(id: "b", displayName: "Blake", avatarColorHex: "#222", role: .member, joinedAt: Date(), seasonWins: 0, seasonLosses: 0),
        ]
        let awards = WeekAwardsEngine.compute(picks: picks, games: games, members: members)
        #expect(awards.sharpshooterUserId == "a")
        #expect(awards.sharpshooterName == "Alex")
    }

    @Test func deepLinkParsesNewNotificationTypes() {
        #expect(DeepLinkRouter.parseNotification(userInfo: ["type": "game_final"]) == .openLiveSlate(groupId: nil))
        #expect(DeepLinkRouter.parseNotification(userInfo: ["type": "took_the_lead"]) == .openLiveSlate(groupId: nil))
        #expect(DeepLinkRouter.parseNotification(userInfo: ["type": "season_closed"]) == .openLeagues(groupId: nil))
        #expect(DeepLinkRouter.parse(url: URL(string: "pickems://discover")!) == .openDiscover)
        #expect(DeepLinkRouter.parse(url: URL(string: "pickems://selections")!) == .openSelections(groupId: nil))
        #expect(DeepLinkRouter.parse(url: URL(string: "pickems://pickems")!) == .openPickems(groupId: nil))
        #expect(
            DeepLinkRouter.parse(url: URL(string: "https://pickems-fb.web.app/join?code=ncaaf1")!)
                == .joinGroup(inviteCode: "NCAAF1")
        )
    }

    private func makeFinal(id: String, home: Int, away: Int) -> SlateGame {
        SlateGame(
            id: id,
            espnEventId: id,
            homeTeamId: "home",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "away",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            spread: 3,
            spreadTeamId: "home",
            kickoff: Date(),
            status: .final,
            homeScore: home,
            awayScore: away,
            winnerTeamId: home > away ? "home" : "away"
        )
    }
}
