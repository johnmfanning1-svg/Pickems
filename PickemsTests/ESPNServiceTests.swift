import Foundation
import Testing
@testable import Pickems

struct ESPNServiceTests {
    @Test func scoreboardURLIncludesFBSGroupsAndLimit() throws {
        let url = try #require(ESPNService.scoreboardURL(week: 1, seasonType: 2))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains(URLQueryItem(name: "groups", value: "80")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "300")))
        #expect(items.contains(URLQueryItem(name: "week", value: "1")))
    }

    @Test func currentWeekURLIncludesFBSGroupsAndLimit() throws {
        let url = try #require(ESPNService.currentWeekURL(seasonType: 2))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains(URLQueryItem(name: "groups", value: "80")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "300")))
        #expect(items.contains(URLQueryItem(name: "seasontype", value: "2")))
    }

    @Test func curatedRank99MapsToNil() throws {
        let json = Data(#"{"current":99}"#.utf8)
        let rank = try JSONDecoder().decode(ESPNScoreboardResponse.ESPNCuratedRank.self, from: json)
        #expect(ESPNService.normalizedCuratedRank(rank) == nil)
    }

    @Test func curatedRankDecodesAndMaps() throws {
        let json = Data(#"{"current":7}"#.utf8)
        let rank = try JSONDecoder().decode(ESPNScoreboardResponse.ESPNCuratedRank.self, from: json)
        #expect(ESPNService.normalizedCuratedRank(rank) == 7)
    }

    @Test func rankedMatchupSetsIsTop25() {
        let ranked = makeGame(homeRank: 5, awayRank: nil)
        let unranked = makeGame(homeRank: nil, awayRank: nil)
        #expect(ranked.isTop25)
        #expect(!unranked.isTop25)
    }

    @Test func competitorJSONDecodesCuratedRankAndConference() throws {
        let json = Data("""
        {
          "id": "c1",
          "homeAway": "home",
          "score": "21",
          "curatedRank": { "current": 99 },
          "team": {
            "id": "333",
            "displayName": "Alabama Crimson Tide",
            "abbreviation": "ALA",
            "conferenceId": "8"
          }
        }
        """.utf8)
        let competitor = try JSONDecoder().decode(ESPNScoreboardResponse.ESPNCompetitor.self, from: json)
        #expect(competitor.curatedRank?.current == 99)
        #expect(ESPNService.normalizedCuratedRank(competitor.curatedRank) == nil)
        #expect(competitor.team.conferenceId == "8")
    }

    @Test func parseSpreadTeamIdFallsBackToDetailsAbbreviation() {
        let odds = ESPNScoreboardResponse.ESPNOdds(
            spread: -7.5,
            details: "BAMA -7.5",
            homeTeamOdds: ESPNScoreboardResponse.ESPNTeamOdds(favorite: nil),
            awayTeamOdds: ESPNScoreboardResponse.ESPNTeamOdds(favorite: nil)
        )
        let teamId = ESPNService.parseSpreadTeamId(
            from: odds,
            homeId: "home",
            awayId: "away",
            homeAbbreviation: "BAMA",
            awayAbbreviation: "AUB"
        )
        #expect(teamId == "home")
    }

    @Test func parseSpreadTeamIdMatchesAwayFromDetails() {
        let odds = ESPNScoreboardResponse.ESPNOdds(
            spread: -3.5,
            details: "OSU -3.5",
            homeTeamOdds: nil,
            awayTeamOdds: nil
        )
        let teamId = ESPNService.parseSpreadTeamId(
            from: odds,
            homeId: "home",
            awayId: "away",
            homeAbbreviation: "MICH",
            awayAbbreviation: "OSU"
        )
        #expect(teamId == "away")
    }

    @Test func conferenceCatalogResolvesKnownIds() {
        #expect(ESPNConferenceCatalog.conference(id: "8")?.shortName == "SEC")
        #expect(ESPNConferenceCatalog.conference(id: "5")?.shortName == "B1G")
        #expect(ESPNConferenceCatalog.conference(id: nil) == nil)
        #expect(ESPNConferenceCatalog.fbs.count == 11)
    }

    @Test func spreadDisplayLabelAlwaysLeadsFavoriteWithMinus() {
        let positiveSpread = ESPNGame(
            id: "1",
            espnEventId: "1",
            competitionId: "c1",
            homeTeamId: "home",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "away",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            kickoff: Date(),
            spread: 7.5,
            spreadTeamId: "home",
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: nil,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil
        )
        #expect(positiveSpread.spreadDisplayLabel == "HOM -7.5")

        let negativeSpread = ESPNGame(
            id: "2",
            espnEventId: "2",
            competitionId: "c2",
            homeTeamId: "home",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "away",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            kickoff: Date(),
            spread: -3,
            spreadTeamId: "away",
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: nil,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil
        )
        #expect(negativeSpread.spreadDisplayLabel == "AWY -3.0")
    }

    private func makeGame(homeRank: Int?, awayRank: Int?) -> ESPNGame {
        ESPNGame(
            id: "1",
            espnEventId: "1",
            competitionId: "c1",
            homeTeamId: "home",
            homeTeamName: "Home",
            homeTeamAbbreviation: "HOM",
            homeTeamLogoURL: nil,
            awayTeamId: "away",
            awayTeamName: "Away",
            awayTeamAbbreviation: "AWY",
            awayTeamLogoURL: nil,
            kickoff: Date(),
            spread: nil,
            spreadTeamId: nil,
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: homeRank,
            awayCuratedRank: awayRank,
            homeConferenceId: "8",
            awayConferenceId: "5"
        )
    }
}
