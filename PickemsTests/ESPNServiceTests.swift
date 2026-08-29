import Foundation
import Testing
@testable import Pickems

struct ESPNServiceTests {
    @Test func parseKickoffDateHandlesFractionalSeconds() {
        let date = ESPNService.parseKickoffDate("2026-09-05T19:30:00.000Z")
        #expect(date != nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 5)
        #expect(parts.hour == 19)
        #expect(parts.minute == 30)
    }

    @Test func parseKickoffDateHandlesPlainISO8601() {
        let fractional = ESPNService.parseKickoffDate("2026-09-05T19:30:00.000Z")
        let plain = ESPNService.parseKickoffDate("2026-09-05T19:30:00Z")
        #expect(fractional == plain)
        #expect(plain != nil)
    }

    @Test func parseKickoffDateHandlesMinutePrecisionESPNDates() {
        // Live ESPN scoreboard currently returns kickoffs without seconds.
        let minutePrecision = ESPNService.parseKickoffDate("2026-08-29T16:00Z")
        #expect(minutePrecision != nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: minutePrecision!)
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 29)
        #expect(parts.hour == 16)
        #expect(parts.minute == 0)
        #expect(parts.second == 0)

        let withOffset = ESPNService.parseKickoffDate("2026-08-29T19:30-04:00")
        #expect(withOffset != nil)
    }

    @Test func parseKickoffDateRejectsGarbage() {
        #expect(ESPNService.parseKickoffDate("not-a-date") == nil)
    }

    @Test func scoreboardURLIncludesFBSGroupsAndLimit() throws {
        let url = try #require(ESPNService.scoreboardURL(week: 1, seasonType: 2))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains(URLQueryItem(name: "groups", value: "80")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "300")))
        #expect(items.contains(URLQueryItem(name: "week", value: "1")))
    }

    @Test func currentWeekURLIncludesFBSGroupsAndLimitWithoutSeasonType() throws {
        let url = try #require(ESPNService.currentWeekURL())
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains(URLQueryItem(name: "groups", value: "80")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "300")))
        #expect(!items.contains(where: { $0.name == "seasontype" }))
        #expect(!items.contains(where: { $0.name == "week" }))
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

    @Test func parseSpreadTeamIdUsesHomeCentricSpreadWhenFlagsAndDetailsMissing() {
        let homeFavorite = ESPNScoreboardResponse.ESPNOdds(
            spread: -4,
            details: nil,
            homeTeamOdds: nil,
            awayTeamOdds: nil
        )
        #expect(
            ESPNService.parseSpreadTeamId(
                from: homeFavorite,
                homeId: "uva",
                awayId: "ncsu",
                homeAbbreviation: "UVA",
                awayAbbreviation: "NCSU"
            ) == "uva"
        )

        let awayFavorite = ESPNScoreboardResponse.ESPNOdds(
            spread: 7.5,
            details: nil,
            homeTeamOdds: nil,
            awayTeamOdds: nil
        )
        #expect(
            ESPNService.parseSpreadTeamId(
                from: awayFavorite,
                homeId: "home",
                awayId: "away",
                homeAbbreviation: "HOM",
                awayAbbreviation: "AWY"
            ) == "away"
        )
    }

    @Test func resolvedSpreadLabelPrefersSlateOverLiveESPN() {
        let espn = ESPNGame(
            id: "401864219",
            espnEventId: "401864219",
            competitionId: "c1",
            homeTeamId: "258",
            homeTeamName: "Virginia Cavaliers",
            homeTeamAbbreviation: "UVA",
            homeTeamLogoURL: nil,
            awayTeamId: "152",
            awayTeamName: "NC State Wolfpack",
            awayTeamAbbreviation: "NCSU",
            awayTeamLogoURL: nil,
            kickoff: Date(),
            spread: -4,
            spreadTeamId: "258",
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: nil,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil
        )
        let invertedSlate = makeSlate(
            id: "401864219",
            espnEventId: "401864219",
            spread: 5.5,
            spreadTeamId: "away",
            homeAbbreviation: "UVA",
            awayAbbreviation: "NCSU"
        )
        #expect(espn.spreadDisplayLabel == "UVA -4.0")
        #expect(
            ESPNService.resolvedSpreadLabel(espnGame: espn, slateGame: invertedSlate) == "NCSU -5.5"
        )
        #expect(ESPNService.resolvedSpreadLabel(espnGame: espn, slateGame: nil) == "UVA -4.0")
        #expect(ESPNService.liveSpreadLabel(espnGame: espn, isSlateGame: true) == "UVA -4.0")
        #expect(ESPNService.liveSpreadLabel(espnGame: espn, isSlateGame: false) == nil)
    }

    @Test func parseBroadcastLabelPrefersNationalName() {
        let broadcasts = [
            ESPNScoreboardResponse.ESPNBroadcast(market: "local", names: ["TBD"]),
            ESPNScoreboardResponse.ESPNBroadcast(market: "national", names: ["ESPN"]),
        ]
        #expect(ESPNService.parseBroadcastLabel(broadcasts: broadcasts, geoBroadcasts: nil) == "ESPN")
        #expect(ESPNService.parseBroadcastLabel(broadcasts: nil, geoBroadcasts: nil) == nil)
        let geo = [
            ESPNScoreboardResponse.ESPNGeoBroadcast(
                media: .init(shortName: "NBC", name: nil)
            )
        ]
        #expect(ESPNService.parseBroadcastLabel(broadcasts: nil, geoBroadcasts: geo) == "NBC")
        #expect(
            ESPNService.parseBroadcastLabel(
                broadcasts: [ESPNScoreboardResponse.ESPNBroadcast(market: "national", names: ["TBD"])],
                geoBroadcasts: geo
            ) == "NBC"
        )
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

    @Test func toSlateGameKeepsHomeFavoriteWhenESPNSpreadIsNegative() {
        // Live ESPN: SJSU @ USC, spread -38.5, homeTeamOdds.favorite = true.
        let uscAtHome = ESPNGame(
            id: "401864494",
            espnEventId: "401864494",
            competitionId: "c1",
            homeTeamId: "30",
            homeTeamName: "USC Trojans",
            homeTeamAbbreviation: "USC",
            homeTeamLogoURL: nil,
            awayTeamId: "23",
            awayTeamName: "San José State Spartans",
            awayTeamAbbreviation: "SJSU",
            awayTeamLogoURL: nil,
            kickoff: Date(),
            spread: -38.5,
            spreadTeamId: "30",
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: nil,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil
        )
        let slate = uscAtHome.toSlateGame()
        #expect(slate.spread == 38.5)
        #expect(slate.spreadTeamId == "30")
        #expect(slate.spreadLabel(for: slate.spreadTeamId) == "-38.5")
    }

    @Test func toSlateGameKeepsAwayFavoriteWhenSpreadIsPositive() {
        let awayFavorite = ESPNGame(
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
            spread: 3.5,
            spreadTeamId: "away",
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: nil,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil
        )
        let slate = awayFavorite.toSlateGame()
        #expect(slate.spread == 3.5)
        #expect(slate.spreadTeamId == "away")
    }

    @Test func nominationFromESPNGameStoresAbsoluteSpread() {
        let espn = ESPNGame(
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
            spread: -4,
            spreadTeamId: "home",
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            homeCuratedRank: nil,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil
        )
        let nom = Nomination.fromESPNGame(espn, submittedBy: "u", submitterName: "Pat")
        #expect(nom.spread == 4)
        #expect(nom.spreadTeamId == "home")
        #expect(nom.asSlateGame().favoriteSpreadDisplay == "HOM -4.0")
    }

    @Test func parseKickoffDateHandlesNewsTimestamps() {
        #expect(ESPNService.parseKickoffDate("2026-08-12T21:10:17Z") != nil)
        #expect(ESPNService.parseKickoffDate("2026-08-12T21:10:17.123Z") != nil)
    }

    @Test func scoreboardCacheKeyDistinguishesWeekAndLive() {
        let browse = ESPNService.ScoreboardCachePolicy.key(week: 1, seasonType: 2, live: false)
        let live = ESPNService.ScoreboardCachePolicy.key(week: 1, seasonType: 2, live: true)
        let otherWeek = ESPNService.ScoreboardCachePolicy.key(week: 2, seasonType: 2, live: false)
        #expect(browse == "2-1-fbs-browse")
        #expect(live == "2-1-fbs-live")
        #expect(browse != live)
        #expect(browse != otherWeek)
    }

    @Test func scoreboardCacheIsFreshWithinTTLButForceRefreshSkipsIt() {
        let now = Date()
        let fetchedAt = now.addingTimeInterval(-30)
        #expect(
            ESPNService.ScoreboardCachePolicy.isFresh(
                fetchedAt: fetchedAt,
                ttl: ESPNService.ScoreboardCachePolicy.liveTTL,
                now: now
            )
        )
        #expect(
            ESPNService.ScoreboardCachePolicy.shouldReturnCached(
                forceRefresh: false,
                fetchedAt: fetchedAt,
                ttl: ESPNService.ScoreboardCachePolicy.liveTTL,
                now: now
            )
        )
        #expect(
            !ESPNService.ScoreboardCachePolicy.shouldReturnCached(
                forceRefresh: true,
                fetchedAt: fetchedAt,
                ttl: ESPNService.ScoreboardCachePolicy.liveTTL,
                now: now
            )
        )
        #expect(
            !ESPNService.ScoreboardCachePolicy.shouldReturnCached(
                forceRefresh: false,
                fetchedAt: now.addingTimeInterval(-120),
                ttl: ESPNService.ScoreboardCachePolicy.liveTTL,
                now: now
            )
        )
        #expect(
            !ESPNService.ScoreboardCachePolicy.shouldReturnCached(
                forceRefresh: false,
                fetchedAt: nil,
                ttl: ESPNService.ScoreboardCachePolicy.liveTTL,
                now: now
            )
        )
    }

    @Test func resolvedPickedTeamIdPrefersEventIdThenSlateId() {
        let slate = makeSlate(id: "firestore-1", espnEventId: "401856766")
        #expect(
            ESPNService.resolvedPickedTeamId(
                espnEventId: "401856766",
                espnGameId: "401856766",
                slateGame: slate,
                userPicks: ["401856766": "home"]
            ) == "home"
        )
        #expect(
            ESPNService.resolvedPickedTeamId(
                espnEventId: "401856766",
                espnGameId: "401856766",
                slateGame: slate,
                userPicks: ["firestore-1": "away"]
            ) == "away"
        )
        #expect(
            ESPNService.resolvedPickedTeamId(
                espnEventId: "401856766",
                espnGameId: "other-id",
                slateGame: nil,
                userPicks: ["other-id": "home"]
            ) == "home"
        )
        #expect(
            ESPNService.resolvedPickedTeamId(
                espnEventId: "401856766",
                espnGameId: "401856766",
                slateGame: slate,
                userPicks: [:]
            ) == nil
        )
    }

    @Test func cardFromSlateMarksGroupAndMyPicks() {
        let slate = makeSlate(id: "firestore-1", espnEventId: "401856766")
        let card = ESPNService.card(from: slate, userPicks: ["firestore-1": "home"])
        #expect(card.isSlateGame)
        #expect(card.hasUserPick)
        #expect(card.userPickTeamAbbreviation == "HOM")
        #expect(card.spreadLabel == "HOM -7.0")
        #expect(card.liveSpreadLabel == nil)
        #expect(card.matches(.groupSlate))
        #expect(card.matches(.myPicks))
        #expect(card.homeCuratedRank == nil)
        #expect(card.awayCuratedRank == nil)
        #expect(!card.isTop25)
    }

    @Test func cardFromSlateAppliesRankLookup() {
        let slate = makeSlate(id: "firestore-1", espnEventId: "401856766")
        let ranks = TeamRankLookup(ranksByTeamId: ["home": 7, "away": 19])
        let card = ESPNService.card(from: slate, userPicks: [:], ranks: ranks)
        #expect(card.homeCuratedRank == 7)
        #expect(card.awayCuratedRank == 19)
        #expect(card.isTop25)
        #expect(card.homeTeamId == "home")
        #expect(card.awayTeamId == "away")
    }

    @Test func liveCardPreservesNumericRanksAndTreats99AsNil() {
        let ranked = makeGame(homeRank: 3, awayRank: 11)
        #expect(ranked.homeCuratedRank == 3)
        #expect(ranked.awayCuratedRank == 11)
        #expect(ranked.isTop25)

        let unranked = makeGame(homeRank: nil, awayRank: nil)
        #expect(unranked.homeCuratedRank == nil)
        #expect(!unranked.isTop25)
    }

    private func makeSlate(
        id: String,
        espnEventId: String,
        spread: Double = 7,
        spreadTeamId: String = "home",
        homeAbbreviation: String = "HOM",
        awayAbbreviation: String = "AWY"
    ) -> SlateGame {
        SlateGame(
            id: id,
            espnEventId: espnEventId,
            homeTeamId: "home",
            homeTeamName: "Home",
            homeTeamAbbreviation: homeAbbreviation,
            homeTeamLogoURL: nil,
            awayTeamId: "away",
            awayTeamName: "Away",
            awayTeamAbbreviation: awayAbbreviation,
            awayTeamLogoURL: nil,
            spread: spread,
            spreadTeamId: spreadTeamId,
            kickoff: Date(),
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            winnerTeamId: nil
        )
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
