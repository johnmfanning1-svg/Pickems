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

    @Test func parseEventPostponedZeroZeroDoesNotShowFinal() async throws {
        let json = Data("""
        {
          "id": "401752866",
          "date": "2026-10-17T19:30:00Z",
          "competitions": [{
            "id": "401752866",
            "competitors": [
              {
                "id": "away",
                "homeAway": "away",
                "score": "0",
                "team": {"id": "2", "displayName": "Auburn Tigers", "abbreviation": "AUB"}
              },
              {
                "id": "home",
                "homeAway": "home",
                "score": "0",
                "team": {"id": "61", "displayName": "Georgia Bulldogs", "abbreviation": "UGA"}
              }
            ],
            "status": {
              "type": {
                "name": "STATUS_POSTPONED",
                "state": "post",
                "completed": true,
                "shortDetail": "Postponed",
                "detail": "Postponed"
              }
            }
          }]
        }
        """.utf8)
        let event = try JSONDecoder().decode(ESPNScoreboardResponse.ESPNEvent.self, from: json)
        let game = try #require(await ESPNService.shared.parseEvent(event))
        #expect(game.status != .final)
        #expect(game.awayScore == 0)
        #expect(game.homeScore == 0)
        #expect(game.statusLabel == "Postponed")

        let detail = SelectionGameDetail.make(
            kickoff: game.kickoff,
            status: game.status,
            awayScore: game.awayScore,
            homeScore: game.homeScore,
            awayAbbreviation: game.awayTeamAbbreviation,
            homeAbbreviation: game.homeTeamAbbreviation,
            statusLabel: game.statusLabel
        )
        #expect(detail.headline == "Postponed")
        #expect(detail.phase != .final)
        #expect(!detail.headline.localizedCaseInsensitiveContains("final"))
        #expect(!detail.accessibilityLabel.localizedCaseInsensitiveContains("final"))
    }

    @Test func canceledSuspendedAndDelayedAreNotFinal() {
        let cases: [(String, String)] = [
            ("STATUS_CANCELED", "Canceled"),
            ("STATUS_SUSPENDED", "Suspended"),
            ("STATUS_DELAYED", "Delayed")
        ]
        for (name, label) in cases {
            let resolved = ESPNService.resolvedSlateStatus(
                name: name,
                state: "post",
                completed: true,
                shortDetail: label,
                detail: nil
            )
            #expect(resolved.status != .final)
            #expect(resolved.label == label)
        }

        let final = ESPNService.resolvedSlateStatus(
            name: "STATUS_FINAL",
            state: "post",
            completed: true,
            shortDetail: "Final",
            detail: "Final"
        )
        #expect(final.status == .final)
        #expect(final.label == nil)

        let detail = SelectionGameDetail.make(
            kickoff: Date(timeIntervalSince1970: 0),
            status: .final,
            awayScore: 0,
            homeScore: 0,
            statusLabel: "Postponed"
        )
        #expect(detail.headline == "Postponed")
        #expect(!detail.headline.contains("Final"))
    }

    @Test func overallRecordSummaryPrefersSeasonTotal() {
        let records = [
            ESPNScoreboardResponse.ESPNRecord(name: "Home", type: "homerecord", summary: "1-1"),
            ESPNScoreboardResponse.ESPNRecord(name: "overall", type: "total", summary: "1-4"),
            ESPNScoreboardResponse.ESPNRecord(name: "Away", type: "awayrecord", summary: "0-3")
        ]
        #expect(ESPNService.overallRecordSummary(records) == "1-4")
        #expect(ESPNService.overallRecordSummary(nil) == nil)
        #expect(ESPNService.overallRecordSummary([]) == nil)
        #expect(
            ESPNService.overallRecordSummary([
                ESPNScoreboardResponse.ESPNRecord(name: "Home", type: "homerecord", summary: "2-0")
            ]) == nil
        )
    }

    @Test func competitorJSONDecodesOverallRecord() throws {
        let json = Data("""
        {
          "id": "c1",
          "homeAway": "away",
          "score": "14",
          "records": [
            {"name": "Home", "type": "homerecord", "summary": "1-1"},
            {"name": "overall", "abbreviation": "overall", "type": "total", "summary": "3-2"}
          ],
          "team": {
            "id": "2",
            "displayName": "Auburn Tigers",
            "abbreviation": "AUB"
          }
        }
        """.utf8)
        let competitor = try JSONDecoder().decode(ESPNScoreboardResponse.ESPNCompetitor.self, from: json)
        #expect(competitor.records?.count == 2)
        #expect(ESPNService.overallRecordSummary(competitor.records) == "3-2")

        let malformed = Data("""
        {
          "id": "c2",
          "homeAway": "home",
          "records": {"total": "5-0"},
          "team": {
            "id": "61",
            "displayName": "Georgia Bulldogs",
            "abbreviation": "UGA"
          }
        }
        """.utf8)
        let stillDecoded = try JSONDecoder().decode(ESPNScoreboardResponse.ESPNCompetitor.self, from: malformed)
        #expect(stillDecoded.team.abbreviation == "UGA")
        #expect(stillDecoded.records == nil)
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

    @Test func liveClockLabelPrefersESPNShortDetail() {
        #expect(
            ESPNService.liveClockLabel(
                shortDetail: "2nd 7:12",
                detail: "2nd Quarter",
                period: 2,
                displayClock: "7:12",
                isInProgress: true
            ) == "2nd 7:12"
        )
        #expect(
            ESPNService.liveClockLabel(
                shortDetail: "Halftime",
                detail: nil,
                period: 2,
                displayClock: "0:00",
                isInProgress: true
            ) == "Halftime"
        )
        #expect(
            ESPNService.liveClockLabel(
                shortDetail: nil,
                detail: "In Progress",
                period: 3,
                displayClock: "4:01",
                isInProgress: true
            ) == "3rd 4:01"
        )
        #expect(
            ESPNService.liveClockLabel(
                shortDetail: "2nd 7:12",
                detail: nil,
                period: 2,
                displayClock: "7:12",
                isInProgress: false
            ) == nil
        )
        #expect(
            ESPNService.liveClockLabel(
                shortDetail: nil,
                detail: nil,
                period: 5,
                displayClock: "5:00",
                isInProgress: true
            ) == "OT 5:00"
        )
    }

    @Test func inProgressStatusDetailIncludesClockAndScore() {
        #expect(
            ESPNService.inProgressStatusDetail(
                awayScore: 15,
                homeScore: 10,
                liveClockLabel: "2nd 7:12"
            ) == "2nd 7:12 · 15-10"
        )
        #expect(
            ESPNService.inProgressStatusDetail(
                awayScore: 15,
                homeScore: 10,
                liveClockLabel: nil
            ) == "Live · 15-10"
        )
        #expect(
            ESPNService.inProgressStatusDetail(
                awayScore: nil,
                homeScore: nil,
                liveClockLabel: "Halftime"
            ) == "Halftime"
        )
    }

    @Test func homeClockLineDropsDuplicateScore() {
        #expect(ESPNLiveGameCard.strippingTrailingScore(from: "4th 4:43 · 15-10") == "4th 4:43")
        #expect(ESPNLiveGameCard.strippingTrailingScore(from: "2nd 7:12 · 15-10") == "2nd 7:12")
        #expect(ESPNLiveGameCard.strippingTrailingScore(from: "Live · 15-10") == "Live")
        #expect(ESPNLiveGameCard.strippingTrailingScore(from: "Final · 21-17") == "Final")
        #expect(ESPNLiveGameCard.strippingTrailingScore(from: "Halftime") == "Halftime")
        #expect(ESPNLiveGameCard.strippingTrailingScore(from: "Upcoming") == "Upcoming")
    }

    @Test func espnStatusDecodesPeriodClockAndShortDetail() throws {
        let json = Data("""
        {
          "clock": 432.0,
          "displayClock": "7:12",
          "period": 2,
          "type": {
            "completed": false,
            "state": "in",
            "shortDetail": "2nd 7:12",
            "detail": "2nd Quarter"
          }
        }
        """.utf8)
        let status = try JSONDecoder().decode(ESPNScoreboardResponse.ESPNStatus.self, from: json)
        #expect(status.period == 2)
        #expect(status.displayClock == "7:12")
        #expect(status.type.state == "in")
        #expect(status.type.shortDetail == "2nd 7:12")
        #expect(!status.type.completed)
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
        let su = ESPNService.card(from: slate, userPicks: ["firestore-1": "home"], pickMode: .straightUp)
        #expect(su.spreadLabel == nil)
        #expect(su.hasUserPick)
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
