import Foundation
import Testing
@testable import Pickems

struct TeamRankLookupTests {
    @Test func buildsFromGamesAndSkipsNilRanks() {
        let games = [
            makeGame(homeId: "ala", homeRank: 5, awayId: "lsu", awayRank: nil),
            makeGame(homeId: "osu", homeRank: 1, awayId: "mich", awayRank: 12),
        ]
        let lookup = TeamRankLookup(games: games)
        #expect(lookup.rank(for: "ala") == 5)
        #expect(lookup.rank(for: "lsu") == nil)
        #expect(lookup.rank(for: "osu") == 1)
        #expect(lookup.rank(for: "mich") == 12)
    }

    @Test func mergeKeepsBetterRank() {
        let a = TeamRankLookup(ranksByTeamId: ["ala": 8, "osu": 3])
        let b = TeamRankLookup(ranksByTeamId: ["ala": 5, "mich": 12])
        let merged = a.merging(b)
        #expect(merged.rank(for: "ala") == 5)
        #expect(merged.rank(for: "osu") == 3)
        #expect(merged.rank(for: "mich") == 12)
    }

    @Test func buildsFromLiveCards() {
        let card = ESPNLiveGameCard(
            id: "1",
            espnEventId: "1",
            awayTeamId: "away",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            homeTeamId: "home",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayScore: nil,
            homeScore: nil,
            spreadLabel: nil,
            status: .scheduled,
            statusDetail: "Upcoming",
            kickoff: Date(),
            isSlateGame: false,
            homeCuratedRank: 4,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil
        )
        let lookup = TeamRankLookup(cards: [card])
        #expect(lookup.rank(for: "home") == 4)
        #expect(lookup.rank(for: "away") == nil)
    }

    @Test func rankedLabelFormatsOnlyValidRanks() {
        #expect(TeamDisplay.rankedLabel(abbreviation: "ALA", rank: nil) == "ALA")
        #expect(TeamDisplay.rankedLabel(abbreviation: "ALA", rank: 5) == "#5 ALA")
        #expect(TeamDisplay.rankedLabel(abbreviation: "ALA", rank: 0) == "ALA")
        #expect(TeamDisplay.rankedLabel(abbreviation: "ALA", rank: 26) == "ALA")
        #expect(TeamDisplay.rankedLabel(abbreviation: "ALA", rank: 99) == "ALA")
    }

    @Test func logoRankTextMatchesESPNScoresList() {
        #expect(TeamDisplay.logoRankText(nil) == nil)
        #expect(TeamDisplay.logoRankText(1) == "1")
        #expect(TeamDisplay.logoRankText(14) == "14")
        #expect(TeamDisplay.logoRankText(25) == "25")
        #expect(TeamDisplay.logoRankText(0) == nil)
        #expect(TeamDisplay.logoRankText(26) == nil)
        #expect(TeamDisplay.logoRankText(99) == nil)
        #expect(TeamDisplay.top25Rank(14) == 14)
        #expect(TeamDisplay.top25Rank(nil) == nil)
    }

    @Test func matchupLabelPrefixesOnlyRankedSides() {
        #expect(
            TeamDisplay.matchupLabel(
                awayAbbreviation: "ALA",
                awayRank: 5,
                homeAbbreviation: "OSU",
                homeRank: nil
            ) == "#5 ALA @ OSU"
        )
        #expect(
            TeamDisplay.matchupLabel(
                awayAbbreviation: "ALA",
                awayRank: nil,
                homeAbbreviation: "OSU",
                homeRank: 12,
                separator: "vs"
            ) == "ALA vs #12 OSU"
        )
    }

    @Test func matchupLabelMarksFavoredSideWithAsterisk() {
        #expect(
            TeamDisplay.matchupLabel(
                awayAbbreviation: "OSU",
                awayRank: 5,
                homeAbbreviation: "UVA",
                homeRank: nil,
                favoredSide: .away
            ) == "#5 OSU* @ UVA"
        )
        #expect(
            TeamDisplay.matchupLabel(
                awayAbbreviation: "OSU",
                awayRank: nil,
                homeAbbreviation: "UVA",
                homeRank: 12,
                favoredSide: .home
            ) == "OSU @ #12 UVA*"
        )
        #expect(
            TeamDisplay.matchupLabel(
                awayAbbreviation: "OSU",
                awayRank: nil,
                homeAbbreviation: "UVA",
                homeRank: nil
            ) == "OSU @ UVA"
        )
    }

    private func makeGame(
        homeId: String,
        homeRank: Int?,
        awayId: String,
        awayRank: Int?
    ) -> ESPNGame {
        ESPNGame(
            id: "\(homeId)-\(awayId)",
            espnEventId: "\(homeId)-\(awayId)",
            competitionId: "c1",
            homeTeamId: homeId,
            homeTeamName: homeId,
            homeTeamAbbreviation: String(homeId.prefix(3)).uppercased(),
            homeTeamLogoURL: nil,
            awayTeamId: awayId,
            awayTeamName: awayId,
            awayTeamAbbreviation: String(awayId.prefix(3)).uppercased(),
            awayTeamLogoURL: nil,
            kickoff: Date(),
            spread: nil,
            spreadTeamId: nil,
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: homeRank,
            awayCuratedRank: awayRank,
            homeConferenceId: nil,
            awayConferenceId: nil
        )
    }
}
