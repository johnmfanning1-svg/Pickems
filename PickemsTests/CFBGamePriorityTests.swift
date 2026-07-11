import Foundation
import Testing
@testable import Pickems

struct CFBGamePriorityTests {
    @Test func rankedGamesOutrankSECAndGroupOf5() {
        let ranked = makeGame(
            id: "ranked",
            homeConferenceId: "5",
            awayConferenceId: "1",
            homeRank: 4,
            awayRank: nil,
            kickoffOffset: 3600
        )
        let sec = makeGame(
            id: "sec",
            homeConferenceId: "8",
            awayConferenceId: "8",
            homeRank: nil,
            awayRank: nil,
            kickoffOffset: 0
        )
        let g5 = makeGame(
            id: "g5",
            homeConferenceId: "37",
            awayConferenceId: "15",
            homeRank: nil,
            awayRank: nil,
            kickoffOffset: 0
        )
        let other = makeGame(
            id: "other",
            homeConferenceId: "5",
            awayConferenceId: "5",
            homeRank: nil,
            awayRank: nil,
            kickoffOffset: 0
        )

        let sorted = [other, g5, sec, ranked].sorted(by: ESPNService.isHigherPriority)
        #expect(sorted.map(\.id) == ["ranked", "sec", "g5", "other"])
    }

    @Test func unrankedSECBeatsGroupOf5AndOtherPowerConferences() {
        let sec = makeGame(
            id: "sec",
            homeConferenceId: "8",
            awayConferenceId: "12",
            homeRank: nil,
            awayRank: nil,
            kickoffOffset: 7200
        )
        let american = makeGame(
            id: "aac",
            homeConferenceId: "151",
            awayConferenceId: "151",
            homeRank: nil,
            awayRank: nil,
            kickoffOffset: 0
        )
        let bigTen = makeGame(
            id: "b1g",
            homeConferenceId: "5",
            awayConferenceId: "5",
            homeRank: nil,
            awayRank: nil,
            kickoffOffset: 0
        )

        #expect(CFBGamePriority.tier(
            homeConferenceId: sec.homeConferenceId,
            awayConferenceId: sec.awayConferenceId,
            homeRank: nil,
            awayRank: nil
        ) == .sec)
        #expect(CFBGamePriority.tier(
            homeConferenceId: american.homeConferenceId,
            awayConferenceId: american.awayConferenceId,
            homeRank: nil,
            awayRank: nil
        ) == .groupOf5)
        #expect(CFBGamePriority.tier(
            homeConferenceId: bigTen.homeConferenceId,
            awayConferenceId: bigTen.awayConferenceId,
            homeRank: nil,
            awayRank: nil
        ) == .other)

        let sorted = [bigTen, american, sec].sorted(by: ESPNService.isHigherPriority)
        #expect(sorted.map(\.id) == ["sec", "aac", "b1g"])
    }

    @Test func withinRankedTierBetterRankComesFirst() {
        let four = makeGame(
            id: "4",
            homeConferenceId: "8",
            awayConferenceId: "1",
            homeRank: 4,
            awayRank: nil,
            kickoffOffset: 7200
        )
        let one = makeGame(
            id: "1",
            homeConferenceId: "5",
            awayConferenceId: "12",
            homeRank: nil,
            awayRank: 1,
            kickoffOffset: 10_000
        )
        let twelve = makeGame(
            id: "12",
            homeConferenceId: "4",
            awayConferenceId: "4",
            homeRank: 12,
            awayRank: 20,
            kickoffOffset: 0
        )

        let sorted = [twelve, four, one].sorted(by: ESPNService.isHigherPriority)
        #expect(sorted.map(\.id) == ["1", "4", "12"])
    }

    @Test func sameTierSortByEarlierKickoff() {
        let later = makeGame(
            id: "later",
            homeConferenceId: "8",
            awayConferenceId: "8",
            homeRank: nil,
            awayRank: nil,
            kickoffOffset: 10_000
        )
        let earlier = makeGame(
            id: "earlier",
            homeConferenceId: "8",
            awayConferenceId: "5",
            homeRank: nil,
            awayRank: nil,
            kickoffOffset: 100
        )

        let sorted = [later, earlier].sorted(by: ESPNService.isHigherPriority)
        #expect(sorted.map(\.id) == ["earlier", "later"])
    }

    @Test func curatedRankNinetyNineIsUnranked() {
        #expect(CFBGamePriority.isRanked(99) == false)
        #expect(CFBGamePriority.isRanked(25) == true)
        #expect(CFBGamePriority.isRanked(nil) == false)
        #expect(CFBGamePriority.bestRank(99, 7) == 7)
        #expect(CFBGamePriority.bestRank(99, nil) == nil)
    }

    private func makeGame(
        id: String,
        homeConferenceId: String?,
        awayConferenceId: String?,
        homeRank: Int?,
        awayRank: Int?,
        kickoffOffset: TimeInterval
    ) -> ESPNGame {
        ESPNGame(
            id: id,
            espnEventId: id,
            competitionId: id,
            homeTeamId: "home-\(id)",
            homeTeamName: "Home \(id)",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            homeConferenceId: homeConferenceId,
            homeRank: homeRank,
            awayTeamId: "away-\(id)",
            awayTeamName: "Away \(id)",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            awayConferenceId: awayConferenceId,
            awayRank: awayRank,
            kickoff: Date(timeIntervalSince1970: 1_700_000_000 + kickoffOffset),
            spread: nil,
            spreadTeamId: nil,
            status: .scheduled,
            homeScore: nil,
            awayScore: nil
        )
    }
}
