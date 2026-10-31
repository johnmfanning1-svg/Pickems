import Foundation
import Testing
@testable import Pickems

struct GamePickRowPresentationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private var morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9))!
    }

    @Test func emptySelectionClearsAndATeamIdStaysSelected() {
        #expect(GamePickRowPresentation.resolvedSelectedTeamId(nil) == nil)
        #expect(GamePickRowPresentation.resolvedSelectedTeamId("") == nil)
        #expect(GamePickRowPresentation.resolvedSelectedTeamId("ucf") == "ucf")
    }

    @Test func explicitRankWinsOverTheLiveRank() {
        #expect(GamePickRowPresentation.resolvedRank(explicit: 22, live: 13) == 22)
        #expect(GamePickRowPresentation.resolvedRank(explicit: nil, live: 13) == 13)
        #expect(GamePickRowPresentation.resolvedRank(explicit: nil, live: nil) == nil)
    }

    @Test func teamAccessibilityMatchesComfortableCopy() {
        let selected = GamePickRowPresentation.teamAccessibility(
            caption: "Home",
            abbreviation: "TTU",
            rank: 13,
            isSelected: true,
            isDisabled: false,
            lockedCaption: nil,
            showsSpread: true
        )
        #expect(selected.label == "Home #13 TTU")
        #expect(selected.hint == "Clear TTU pick")
        #expect(selected.isSelected)

        let open = GamePickRowPresentation.teamAccessibility(
            caption: "Away",
            abbreviation: "ARIZ",
            rank: nil,
            isSelected: false,
            isDisabled: false,
            lockedCaption: nil,
            showsSpread: true
        )
        #expect(open.label == "Away ARIZ")
        #expect(open.hint == "Select ARIZ against the spread")
        #expect(!open.isSelected)

        let straightUp = GamePickRowPresentation.teamAccessibility(
            caption: "Away",
            abbreviation: "WIS",
            rank: nil,
            isSelected: false,
            isDisabled: false,
            lockedCaption: nil,
            showsSpread: false
        )
        #expect(straightUp.hint == "Select WIS to win")
    }

    @Test func disabledHintUsesTheBlockCaption() {
        let blocked = GamePickRowPresentation.teamAccessibility(
            caption: "Away",
            abbreviation: "BAY",
            rank: nil,
            isSelected: false,
            isDisabled: true,
            lockedCaption: "Postponed",
            showsSpread: true
        )
        #expect(blocked.hint == "Postponed")

        let locked = GamePickRowPresentation.teamAccessibility(
            caption: "Home",
            abbreviation: "UCF",
            rank: nil,
            isSelected: false,
            isDisabled: true,
            lockedCaption: nil,
            showsSpread: true
        )
        #expect(locked.hint == "Pickems are locked")
    }

    @Test func scheduledTodayOmitsTheDayAndAnotherDayPrefixesIt() {
        let today = game(kickoff: calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!)
        let column = GamePickRowPresentation.statusColumn(
            game: today,
            liveCard: nil,
            isDisabled: false,
            now: morning,
            calendar: calendar
        )
        let time = GamePickRowPresentation.compactTime(today.kickoff, calendar: calendar)
        #expect(column == .scheduled(time: time))
        #expect(!time.contains("AM"))
        #expect(!time.contains("PM"))

        let tomorrowKickoff = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let tomorrow = game(kickoff: tomorrowKickoff)
        let later = GamePickRowPresentation.statusColumn(
            game: tomorrow,
            liveCard: nil,
            isDisabled: false,
            now: morning,
            calendar: calendar
        )
        let laterTime = GamePickRowPresentation.compactTime(tomorrowKickoff, calendar: calendar)
        let day = GamePickRowPresentation.weekdayAbbreviation(tomorrowKickoff, calendar: calendar)
        #expect(later == .scheduled(time: "\(day) \(laterTime)"))
        #expect(day == "Sun")
    }

    @Test func lockedScheduledGameShowsTheLockColumn() {
        let kickoff = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
        let slate = game(kickoff: kickoff)
        let column = GamePickRowPresentation.statusColumn(
            game: slate,
            liveCard: nil,
            isDisabled: true,
            now: morning,
            calendar: calendar
        )
        let time = GamePickRowPresentation.compactTime(kickoff, calendar: calendar)
        #expect(column == .locked(time: time))
        #expect(
            GamePickRowPresentation.statusAccessibilityLabel(
                column: column,
                kickoffMetaLine: slate.kickoffMetaLine,
                statusDetail: nil,
                lockedCaption: "Locked at kickoff"
            ) == "Locked at kickoff. \(slate.kickoffMetaLine)"
        )
    }

    @Test func liveColumnUsesScoreAndQuarter() {
        let slate = game(status: .inProgress, awayScore: 21, homeScore: 14)
        let live = card(status: .inProgress, awayScore: 21, homeScore: 14, statusDetail: "3rd 7:12 · 21-14")
        let column = GamePickRowPresentation.statusColumn(
            game: slate,
            liveCard: live,
            isDisabled: true,
            now: morning,
            calendar: calendar
        )
        #expect(column == .live(score: "21\u{2013}14", period: "Q3"))
    }

    @Test func compactPeriodMapsClockLanguage() {
        #expect(GamePickRowPresentation.compactPeriod(from: "1st 12:00 · 0-0") == "Q1")
        #expect(GamePickRowPresentation.compactPeriod(from: "Halftime · 10-7") == "HT")
        #expect(GamePickRowPresentation.compactPeriod(from: "OT 2:01 · 24-24") == "OT")
        #expect(GamePickRowPresentation.compactPeriod(from: "Q4 0:12 · 28-27") == "Q4")
        #expect(GamePickRowPresentation.compactPeriod(from: "Live · 7-3") == "")
    }

    @Test func finalColumnsCarryTheResult() {
        let slate = game(status: .final, awayScore: 41, homeScore: 9)
        let won = GamePickRowPresentation.statusColumn(
            game: slate,
            liveCard: card(status: .final, awayScore: 41, homeScore: 9, statusDetail: "Final · 41-9", result: .win),
            isDisabled: true,
            now: morning,
            calendar: calendar
        )
        #expect(won == .final(label: "F 41\u{2013}9", result: .win))

        let lost = GamePickRowPresentation.statusColumn(
            game: slate,
            liveCard: card(status: .final, awayScore: 41, homeScore: 9, statusDetail: "Final", result: .loss),
            isDisabled: true,
            now: morning,
            calendar: calendar
        )
        #expect(lost == .final(label: "F 41\u{2013}9", result: .loss))

        let push = GamePickRowPresentation.statusColumn(
            game: slate,
            liveCard: card(status: .final, awayScore: 24, homeScore: 21, statusDetail: "Final", result: .push),
            isDisabled: true,
            now: morning,
            calendar: calendar
        )
        #expect(push == .final(label: "F 24\u{2013}21", result: .push))

        let unscored = GamePickRowPresentation.statusColumn(
            game: game(status: .final),
            liveCard: nil,
            isDisabled: true,
            now: morning,
            calendar: calendar
        )
        #expect(unscored == .final(label: "F", result: nil))
    }

    @Test func finalAccessibilitySpeaksTheComfortableResultName() {
        let slate = game(status: .final, awayScore: 41, homeScore: 9)
        let column = GamePickRowPresentation.StatusColumn.final(label: "F 41–9", result: .loss)
        let spoken = GamePickRowPresentation.statusAccessibilityLabel(
            column: column,
            kickoffMetaLine: slate.kickoffMetaLine,
            statusDetail: "Final · 41-9",
            lockedCaption: nil
        )
        #expect(spoken == "Final · 41-9. Loss. \(slate.kickoffMetaLine)")
        #expect(GamePickRowPresentation.resultSpokenName(.win) == "Win")
        #expect(GamePickRowPresentation.resultSpokenName(.push) == "Push")
        #expect(GamePickRowPresentation.resultSpokenName(.pending) == "Pending")
    }

    @Test func spreadSuffixLandsOnTheFavoriteOnly() {
        let homeFavorite = game(spread: 3.5, spreadTeamId: "home")
        #expect(GamePickRowPresentation.spreadSuffix(game: homeFavorite, teamId: "home", showsSpread: true) == "-3.5")
        #expect(GamePickRowPresentation.spreadSuffix(game: homeFavorite, teamId: "away", showsSpread: true) == nil)
        #expect(GamePickRowPresentation.spreadSuffix(game: homeFavorite, teamId: "home", showsSpread: false) == nil)

        let pickEm = game(spread: 0, spreadTeamId: "home")
        #expect(GamePickRowPresentation.spreadSuffix(game: pickEm, teamId: "home", showsSpread: true) == nil)

        #expect(GamePickRowPresentation.pillTitle(abbreviation: "TTU", rank: 13, spreadSuffix: "-3.5") == "#13 TTU -3.5")
        #expect(GamePickRowPresentation.pillTitle(abbreviation: "BAY", rank: nil, spreadSuffix: nil) == "BAY")
    }

    @Test func lineInfoAppearsOnlyWhenTheMarketLineMoved() {
        #expect(
            GamePickRowPresentation.lineInfoMessage(locked: "UCF -1.5", live: "UCF -2.5", isFinal: false)?
                .contains("Current line: UCF -2.5") == true
        )
        #expect(GamePickRowPresentation.lineInfoMessage(locked: "UCF -1.5", live: "UCF -1.5", isFinal: false) == nil)
        #expect(GamePickRowPresentation.lineInfoMessage(locked: "UCF -1.5", live: nil, isFinal: false) == nil)
    }

    private func game(
        kickoff: Date? = nil,
        status: SlateGame.GameStatus = .scheduled,
        spread: Double = 1.5,
        spreadTeamId: String = "home",
        awayScore: Int? = nil,
        homeScore: Int? = nil
    ) -> SlateGame {
        SlateGame(
            id: "401",
            espnEventId: "401",
            homeTeamId: "home",
            homeTeamName: "UCF",
            homeTeamAbbreviation: "UCF",
            homeTeamLogoURL: nil,
            awayTeamId: "away",
            awayTeamName: "Baylor",
            awayTeamAbbreviation: "BAY",
            awayTeamLogoURL: nil,
            spread: spread,
            spreadTeamId: spreadTeamId,
            kickoff: kickoff ?? morning,
            status: status,
            homeScore: homeScore,
            awayScore: awayScore,
            winnerTeamId: nil
        )
    }

    private func card(
        status: SlateGame.GameStatus,
        awayScore: Int?,
        homeScore: Int?,
        statusDetail: String,
        result: ESPNLiveGameCard.PickResult? = nil
    ) -> ESPNLiveGameCard {
        ESPNLiveGameCard(
            id: "401",
            espnEventId: "401",
            awayTeamId: "away",
            awayTeamName: "Baylor",
            awayTeamAbbreviation: "BAY",
            awayTeamLogoURL: nil,
            homeTeamId: "home",
            homeTeamName: "UCF",
            homeTeamAbbreviation: "UCF",
            homeTeamLogoURL: nil,
            awayScore: awayScore,
            homeScore: homeScore,
            spreadLabel: "UCF -1.5",
            status: status,
            statusDetail: statusDetail,
            kickoff: morning,
            isSlateGame: true,
            homeCuratedRank: nil,
            awayCuratedRank: nil,
            homeConferenceId: nil,
            awayConferenceId: nil,
            pickResult: result
        )
    }
}
