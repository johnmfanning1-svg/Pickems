import Foundation
import Testing
@testable import Pickems

struct SeasonLedgerTests {
    // MARK: - Refresh failure presentation

    @Test func staleRefreshErrorWithDataShowsBannerNotFullError() {
        let data = minimalSeasonData()
        let error = "Couldn't load that right now."
        #expect(SeasonLedgerLoader.showsRefreshFailureBanner(errorMessage: error, data: data))
        #expect(!SeasonLedgerLoader.showsFullLoadError(errorMessage: error, data: data, isLoading: false))
    }

    @Test func loadErrorWithNoDataShowsFullErrorNotBanner() {
        let error = "Couldn't load that right now."
        #expect(!SeasonLedgerLoader.showsRefreshFailureBanner(errorMessage: error, data: nil))
        #expect(SeasonLedgerLoader.showsFullLoadError(errorMessage: error, data: nil, isLoading: false))
    }

    @Test func successfulReloadClearsRefreshBannerState() {
        let data = minimalSeasonData()
        #expect(!SeasonLedgerLoader.showsRefreshFailureBanner(errorMessage: nil, data: data))
        #expect(!SeasonLedgerLoader.showsFullLoadError(errorMessage: nil, data: data, isLoading: false))
    }

    @Test func refreshErrorClearsWhenLeagueOrViewerChanges() {
        #expect(SeasonLedgerLoader.shouldClearRefreshError(cachedKey: "g1|u1", groupId: "g2", viewerId: "u1"))
        #expect(SeasonLedgerLoader.shouldClearRefreshError(cachedKey: "g1|u1", groupId: "g1", viewerId: "u2"))
        #expect(!SeasonLedgerLoader.shouldClearRefreshError(cachedKey: "g1|u1", groupId: "g1", viewerId: "u1"))
        #expect(!SeasonLedgerLoader.shouldClearRefreshError(cachedKey: nil, groupId: "g1", viewerId: "u1"))
    }

    // MARK: - Highlights

    @Test func uniqueWeeklyHighIsBest() {
        let highlights = SeasonLedgerHighlight.winHighlights(weeklyWinsByMemberId: [
            "a": 8, "b": 6, "c": 5,
        ])
        #expect(highlights["a"] == SeasonLedgerWinHighlight.best)
        #expect(highlights["b"] == SeasonLedgerWinHighlight.none)
        #expect(highlights["c"] == SeasonLedgerWinHighlight.none)
    }

    @Test func twoWayTieForHighIsGold() {
        let highlights = SeasonLedgerHighlight.winHighlights(weeklyWinsByMemberId: [
            "a": 7, "b": 7, "c": 4,
        ])
        #expect(highlights["a"] == SeasonLedgerWinHighlight.tie)
        #expect(highlights["b"] == SeasonLedgerWinHighlight.tie)
        #expect(highlights["c"] == SeasonLedgerWinHighlight.none)
    }

    @Test func threeWayTieForHighIsGoldForAllLeaders() {
        let highlights = SeasonLedgerHighlight.winHighlights(weeklyWinsByMemberId: [
            "a": 5, "b": 5, "c": 5, "d": 2,
        ])
        #expect(highlights["a"] == SeasonLedgerWinHighlight.tie)
        #expect(highlights["b"] == SeasonLedgerWinHighlight.tie)
        #expect(highlights["c"] == SeasonLedgerWinHighlight.tie)
        #expect(highlights["d"] == SeasonLedgerWinHighlight.none)
    }

    @Test func allMembersEqualProducesNoHighlight() {
        let highlights = SeasonLedgerHighlight.winHighlights(weeklyWinsByMemberId: [
            "a": 0, "b": 0, "c": 0,
        ])
        #expect(highlights.values.allSatisfy { $0 == SeasonLedgerWinHighlight.none })
    }

    @Test func uniqueBowlsWeekHighIsBest() {
        let highlights = SeasonLedgerHighlight.winHighlights(weeklyWinsByMemberId: [
            "a": 3, "b": 2, "c": 2,
        ])
        #expect(highlights["a"] == SeasonLedgerWinHighlight.best)
    }

    // MARK: - Games back

    @Test func soleLeaderShowsEvenEmDash() {
        #expect(SeasonLedgerGamesBack.caption(memberWins: 20, leaderWins: 20) == "—")
        #expect(SeasonLedgerGamesBack.caption(memberWins: 10, leaderWins: 20) == "−10")
    }

    @Test func coLeaderEvenWhenLossesDiffer() {
        let leader = SeasonLedgerGamesBack.leaderWins(memberSeasonWins: ["a": 14, "b": 14, "c": 10])
        #expect(leader == 14)
        #expect(SeasonLedgerGamesBack.caption(memberWins: 14, leaderWins: leader) == "—")
        #expect(SeasonLedgerGamesBack.caption(memberWins: 10, leaderWins: leader) == "−4")
    }

    @Test func gamesBackUsesStandingsGapWinArithmetic() {
        #expect(StandingsGap.gamesAhead(youWins: 14, themWins: 10) == 4)
        #expect(SeasonLedgerGamesBack.caption(memberWins: 10, leaderWins: 14) == "−4")
    }

    // MARK: - Totals

    @Test func weekTotalsMatchPerGameScoring() {
        let games = [
            finalGame(id: "g1", homeWins: true),
            finalGame(id: "g2", homeWins: false),
        ]
        let members = [member("a", "Alex")]
        let picks: [String: UserPick] = [
            "a": pick(userId: "a", choices: ["g1": "home", "g2": "away"]),
        ]
        let records = SeasonLedgerAggregator.memberRecords(
            members: members,
            games: games,
            picksByUserId: picks,
            hiddenGameIds: [],
            viewerId: "a",
            pickMode: .ats
        )
        #expect(records["a"]?.wins == 2)
        #expect(records["a"]?.losses == 0)
    }

    @Test func missedFinalPickCountsAsLoss() {
        let games = [finalGame(id: "g1", homeWins: true)]
        let members = [member("a", "Alex")]
        let records = SeasonLedgerAggregator.memberRecords(
            members: members,
            games: games,
            picksByUserId: [:],
            hiddenGameIds: [],
            viewerId: nil,
            pickMode: .ats
        )
        #expect(records["a"]?.wins == 0)
        #expect(records["a"]?.losses == 1)
    }

    @Test func seasonWLPSumsAcrossWeekBoards() {
        let week1 = SeasonLedgerWeekBoard(
            week: weekSummary(id: "2026-W1", number: 1),
            games: [],
            picksByUserId: [:],
            hiddenGameIds: [],
            recordsByMemberId: ["a": .init(wins: 3, losses: 1, pushes: 0)],
            pickMode: .ats
        )
        let week2 = SeasonLedgerWeekBoard(
            week: weekSummary(id: "2026-W2", number: 2),
            games: [],
            picksByUserId: [:],
            hiddenGameIds: [],
            recordsByMemberId: ["a": .init(wins: 2, losses: 2, pushes: 1)],
            pickMode: .ats
        )
        let data = SeasonLedgerSeasonData(groupId: "g", weeks: [week1, week2], memberIds: ["a"])
        let season = data.seasonRecord(for: "a")
        #expect(season.wins == 5)
        #expect(season.losses == 3)
        #expect(season.pushes == 1)
    }

    // MARK: - Privacy

    @Test func hiddenGameBlocksOtherMembersPickDisplay() {
        #expect(
            SeasonLedgerPrivacy.mayShowPick(
                gameId: "g1",
                memberId: "b",
                viewerId: "a",
                hiddenGameIds: ["g1"]
            ) == false
        )
        #expect(
            SeasonLedgerPrivacy.mayShowPick(
                gameId: "g1",
                memberId: "a",
                viewerId: "a",
                hiddenGameIds: ["g1"]
            )
        )
    }

    @Test func publicWeekHasNoHiddenGames() {
        let week = weekSummary(id: "2026-W3", number: 3, status: .scored)
        let games = [finalGame(id: "g1", homeWins: true)]
        #expect(SeasonLedgerPrivacy.hiddenGameIds(week: week, games: games).isEmpty)
    }

    @Test func rollingLockHidesUnstartedGames() {
        var week = weekSummary(id: "2026-W4", number: 4, status: .picking)
        week.pickLockMode = .rolling
        week.pickDeadline = Date().addingTimeInterval(-60)
        week.remainingLockAt = Date().addingTimeInterval(3600)
        let games = [
            scheduledGame(id: "open"),
            finalGame(id: "done", homeWins: true),
        ]
        let hidden = SeasonLedgerPrivacy.hiddenGameIds(week: week, games: games)
        #expect(hidden.contains("open"))
        #expect(!hidden.contains("done"))
    }

    // MARK: - Layout

    @Test func wideRosterUsesSingleSharedMemberScroll() {
        #expect(SeasonLedgerMemberTableLayout.usesSharedHorizontalScroll(memberCount: 5))
        #expect(!SeasonLedgerMemberTableLayout.usesSharedHorizontalScroll(memberCount: 4))
        #expect(SeasonLedgerMemberTableLayout.sharedScrollMemberThreshold == 4)
    }

    // MARK: - Week eligibility

    @Test func eligibleWeeksStayInCurrentSeasonYear() {
        let weeks = [
            weekSummary(id: "2025-W10", number: 10, status: .scored, seasonYear: 2025),
            weekSummary(id: "2026-W2", number: 2, status: .scored, seasonYear: 2026),
            weekSummary(id: "2026-W3", number: 3, status: .locked, seasonYear: 2026),
        ]
        let eligible = SeasonLedgerWeekEligibility.eligibleWeeks(from: weeks, seasonYear: 2026)
        #expect(eligible.map(\.id) == ["2026-W2", "2026-W3"])
    }

    @Test func duplicateWeekNumbersFromOtherSeasonsAreExcluded() {
        let weeks = [
            weekSummary(id: "2025-W5", number: 5, status: .scored, seasonYear: 2025),
            weekSummary(id: "2026-W5", number: 5, status: .scored, seasonYear: 2026),
        ]
        let eligible = SeasonLedgerWeekEligibility.eligibleWeeks(from: weeks, seasonYear: 2026)
        #expect(eligible.count == 1)
        #expect(eligible[0].id == "2026-W5")
    }

    @Test func pickingWeekBeforeDeadlineIsExcluded() {
        var week = weekSummary(id: "2026-W6", number: 6, status: .picking, seasonYear: 2026)
        week.pickDeadline = Date().addingTimeInterval(3600)
        let now = Date()
        #expect(!SeasonLedgerWeekEligibility.isEligible(week, now: now))
    }

    @Test func pushCountsThroughAggregator() {
        let game = pushGame(id: "g-push")
        let members = [member("a", "Alex")]
        let picks: [String: UserPick] = [
            "a": pick(userId: "a", choices: ["g-push": "home"]),
        ]
        let records = SeasonLedgerAggregator.memberRecords(
            members: members,
            games: [game],
            picksByUserId: picks,
            hiddenGameIds: [],
            viewerId: "a",
            pickMode: .ats
        )
        #expect(records["a"]?.pushes == 1)
        #expect(records["a"]?.wins == 0)
        #expect(records["a"]?.losses == 0)
        let status = SeasonLedgerAggregator.pickCellStatus(
            game: game,
            pickedTeamId: "home",
            pickMode: .ats
        )
        #expect(status == PickBoardStatus.push)
    }

    // MARK: - Week title

    @Test func armyNavyWeekTitleFromId() {
        let week = weekSummary(id: "2026-army-navy", number: 15)
        #expect(SeasonLedgerWeekTitle.rowTitle(for: week) == "Army Navy")
    }

    // MARK: - Helpers

    private func member(_ id: String, _ name: String) -> GroupMember {
        GroupMember(
            id: id,
            displayName: name,
            avatarColorHex: "#424242",
            role: .member,
            joinedAt: Date(),
            seasonWins: 0,
            seasonLosses: 0
        )
    }

    private func pick(userId: String, choices: [String: String]) -> UserPick {
        UserPick(
            id: userId,
            userId: userId,
            displayName: userId,
            picks: choices,
            submittedAt: nil,
            isLocked: true
        )
    }

    private func minimalSeasonData(groupId: String = "g1") -> SeasonLedgerSeasonData {
        SeasonLedgerSeasonData(
            groupId: groupId,
            weeks: [
                SeasonLedgerWeekBoard(
                    week: weekSummary(id: "2026-W1", number: 1),
                    games: [],
                    picksByUserId: [:],
                    hiddenGameIds: [],
                    recordsByMemberId: ["a": .init(wins: 1, losses: 0, pushes: 0)],
                    pickMode: .ats
                ),
            ],
            memberIds: ["a"]
        )
    }

    private func weekSummary(
        id: String,
        number: Int,
        status: WeekStatus = .scored,
        seasonYear: Int = 2026
    ) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: seasonYear,
            weekNumber: number,
            status: status,
            slateSize: 10,
            selectionMode: .member,
            selectionsPerMember: 3,
            nominationCount: 0
        )
    }

    private func finalGame(id: String, homeWins: Bool) -> SlateGame {
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
            spread: homeWins ? 7 : -7,
            spreadTeamId: "home",
            kickoff: Date(timeIntervalSince1970: 0),
            status: .final,
            homeScore: homeWins ? 28 : 10,
            awayScore: homeWins ? 10 : 28,
            winnerTeamId: homeWins ? "home" : "away"
        )
    }

    private func pushGame(id: String) -> SlateGame {
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
            kickoff: Date(timeIntervalSince1970: 0),
            status: .final,
            homeScore: 20,
            awayScore: 17,
            winnerTeamId: "home"
        )
    }

    private func scheduledGame(id: String) -> SlateGame {
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
            kickoff: Date().addingTimeInterval(3600),
            status: .scheduled,
            homeScore: nil,
            awayScore: nil,
            winnerTeamId: nil
        )
    }
}