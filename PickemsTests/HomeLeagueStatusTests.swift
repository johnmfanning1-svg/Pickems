import Foundation
import Testing
@testable import Pickems

struct HomeLeagueStatusTests {
    @Test func scorelessWeekAndSeasonDoNotBecomeFirst() {
        let board = [standing(id: "me", rank: 1, tied: false, weeklyWins: 0, weeklyLosses: 0, seasonWins: 0, seasonLosses: 0)]
        let model = HomeLeagueStatus.make(
            leagueName: "Saturday",
            weekNumber: 11,
            weekStatus: .picking,
            progress: HomeLeagueStatus.Progress(picksMade: 0, picksNeeded: 8),
            weeklyEntry: board[0],
            weeklyBoard: board,
            seasonEntry: board[0],
            seasonBoard: board
        )

        #expect(model.week.recordText == "\u{2014}")
        #expect(model.week.rankText == "\u{2014}")
        #expect(model.week.animatableRank == nil)
        #expect(model.week.rankText != "#1")
        #expect(model.season.recordText == "0\u{2013}0")
        #expect(model.season.rankText == "\u{2014}")
        #expect(model.season.animatableRank == nil)
        #expect(model.stage == .pickems)
        #expect(model.detail == "8 Pickems to make")
        #expect(model.accessibilityLabel.contains("This week, no result yet"))

        let pushOnly = HomeLeagueStatus.make(
            leagueName: "Saturday",
            weekNumber: 11,
            weekStatus: .picking,
            weeklyPushes: 3,
            weeklyEntry: board[0],
            weeklyBoard: board,
            seasonEntry: board[0],
            seasonBoard: board
        )
        #expect(pushOnly.week.recordText == "All pushes this week")
        #expect(pushOnly.week.rankText == "\u{2014}")
        #expect(pushOnly.week.rankText != "#1")
        #expect(pushOnly.week.animatableRank == nil)
        #expect(pushOnly.season.recordText == "0\u{2013}0")
        #expect(pushOnly.season.rankText == "\u{2014}")
        #expect(pushOnly.accessibilityLabel.contains("All pushes this week"))
        #expect(!pushOnly.accessibilityLabel.contains("no result yet"))
        #expect(!pushOnly.accessibilityLabel.contains("No games final yet"))
    }

    @Test func weekAndSeasonUseTheirOwnRecordsAndRanks() {
        let meWeek = standing(id: "me", rank: 4, tied: true, weeklyWins: 3, weeklyLosses: 2, seasonWins: 1, seasonLosses: 0)
        let peerWeek = standing(id: "them", rank: 4, tied: true, weeklyWins: 3, weeklyLosses: 2, seasonWins: 9, seasonLosses: 9)
        let meSeason = standing(id: "me", rank: 1, tied: false, weeklyWins: 0, weeklyLosses: 0, seasonWins: 20, seasonLosses: 8)
        let model = HomeLeagueStatus.make(
            leagueName: "Saturday",
            weekNumber: 11,
            weekStatus: .scored,
            weeklyEntry: meWeek,
            weeklyBoard: [meWeek, peerWeek],
            seasonEntry: meSeason,
            seasonBoard: [meSeason]
        )

        #expect(model.week.recordText == "3\u{2013}2")
        #expect(model.week.rankText == "T-#4")
        #expect(model.week.animatableRank == 4)
        #expect(model.season.recordText == "20\u{2013}8")
        #expect(model.season.rankText == "#1")
        #expect(model.season.animatableRank == 1)
        #expect(model.stage == .final)
        #expect(model.detail == nil)
        #expect(model.weekLabel == "Week 11")
    }

    @Test func tiePrefixFollowsTheHomeRankRule() {
        let me = standing(id: "me", rank: 2, tied: false, weeklyWins: 4, weeklyLosses: 1, seasonWins: 4, seasonLosses: 1)
        let peer = standing(id: "them", rank: 2, tied: true, weeklyWins: 4, weeklyLosses: 1, seasonWins: 4, seasonLosses: 1)
        let shared = HomeLeagueStatus.make(
            leagueName: "Saturday",
            weekNumber: 8,
            weekStatus: .locked,
            weeklyEntry: me,
            weeklyBoard: [me, peer],
            seasonEntry: me,
            seasonBoard: [me]
        )
        #expect(shared.week.rankText == "T-#2")
        #expect(shared.week.accessibilityRank == "Tied for rank 2")
        #expect(shared.season.rankText == "#2")

        let solo = HomeLeagueStatus.make(
            leagueName: "Saturday",
            weekNumber: 8,
            weekStatus: .locked,
            weeklyEntry: me,
            weeklyBoard: [me],
            seasonEntry: me,
            seasonBoard: [me]
        )
        #expect(solo.week.rankText == "#2")
        #expect(solo.week.accessibilityRank == "Rank 2")
    }

    @Test func selectionsEarlyWeekShowsProgressAndKeepsTheSeason() {
        let week = standing(id: "me", rank: 1, tied: false, weeklyWins: 0, weeklyLosses: 0, seasonWins: 11, seasonLosses: 7)
        let season = standing(id: "me", rank: 2, tied: false, weeklyWins: 0, weeklyLosses: 0, seasonWins: 11, seasonLosses: 7)
        let model = HomeLeagueStatus.make(
            leagueName: "Buckeyes",
            weekNumber: 11,
            weekStatus: .selection,
            progress: HomeLeagueStatus.Progress(selectionsMade: 3, selectionsNeeded: 8),
            weeklyEntry: week,
            weeklyBoard: [week],
            seasonEntry: season,
            seasonBoard: [season]
        )

        #expect(model.stage == .selections)
        #expect(model.detail == "3 of 8 selections")
        #expect(model.week.recordText == "\u{2014}")
        #expect(model.week.rankText == "\u{2014}")
        #expect(model.season.recordText == "11\u{2013}7")
        #expect(model.season.rankText == "#2")
        #expect(model.leagueName == "Buckeyes")
        #expect(model.accessibilityLabel.contains("Selections"))
        #expect(model.accessibilityLabel.contains("This week, no result yet"))
        #expect(model.accessibilityLabel.contains("Season 11 to 7, Rank 2"))
    }

    @Test func pickemsCopyCountsWhatIsLeft() {
        let open = status(status: .picking, progress: .init(picksMade: 6, picksNeeded: 8))
        #expect(open.stage == .pickems)
        #expect(open.detail == "2 Pickems left")
        #expect(open.week.recordText == "\u{2014}")

        let none = status(status: .picking, progress: .init(picksMade: 0, picksNeeded: 8))
        #expect(none.detail == "8 Pickems to make")

        let oneToMake = status(status: .picking, progress: .init(picksMade: 0, picksNeeded: 1))
        #expect(oneToMake.detail == "1 Pickem to make")

        let one = status(status: .picking, progress: .init(picksMade: 7, picksNeeded: 8))
        #expect(one.detail == "1 Pickem left")

        let done = status(status: .picking, progress: .init(picksMade: 8, picksNeeded: 8))
        #expect(done.detail == "Pickems in")

        let submitted = status(status: .selection, progress: .init(selectionsMade: 3, selectionsNeeded: 3))
        #expect(submitted.detail == "Selections in")
    }

    @Test func waitingOnSelectionsDoesNotInventAWeeklyResult() {
        let model = status(
            status: .selection,
            progress: .init(selectionsMade: 4, selectionsNeeded: 8, waitingOnSelections: true)
        )
        #expect(model.stage == .selections)
        #expect(model.detail == "Waiting on selections")
        #expect(model.week.rankText == "\u{2014}")
        #expect(model.week.recordText == "\u{2014}")
    }

    @Test func stageFollowsLockLiveAndFinal() {
        let locked = status(
            status: .picking,
            picksFullyLocked: true,
            progress: .init(gamesFinal: 2, gamesOnSlate: 8)
        )
        #expect(locked.stage == .locked)
        #expect(locked.detail == "2 of 8 final")

        let quietLock = status(status: .locked, picksFullyLocked: true)
        #expect(quietLock.stage == .locked)
        #expect(quietLock.detail == nil)

        let oneLive = status(status: .locked, progress: .init(gamesLive: 1, gamesOnSlate: 8))
        #expect(oneLive.stage == .live)
        #expect(oneLive.detail == "1 game live")
        #expect(oneLive.week.recordText == "\u{2014}")

        let rolling = status(status: .picking, picksFullyLocked: false, progress: .init(gamesLive: 3))
        #expect(rolling.stage == .live)
        #expect(rolling.detail == "3 games live")

        let final = status(
            status: .scored,
            progress: .init(gamesLive: 1, gamesFinal: 8, gamesOnSlate: 8),
            weeklyWins: 5,
            weeklyLosses: 3,
            rank: 1
        )
        #expect(final.stage == .final)
        #expect(final.detail == nil)
        #expect(final.week.recordText == "5\u{2013}3")
        #expect(final.week.rankText == "#1")
    }

    @Test func fixedSlateSkipsTheSelectionStage() {
        let model = status(status: .selection, skipsSelection: true, progress: .init(picksMade: 1, picksNeeded: 8))
        #expect(model.stage == .pickems)
        #expect(model.detail == "7 Pickems left")
    }

    @Test func unloadedWeekAndMissingStandingStayBlank() {
        let stale = standing(id: "me", rank: 1, tied: false, weeklyWins: 6, weeklyLosses: 2, seasonWins: 6, seasonLosses: 2)
        let unloaded = HomeLeagueStatus.make(
            leagueName: "Saturday",
            weekNumber: nil,
            weekStatus: nil,
            weeklyEntry: stale,
            weeklyBoard: [stale],
            seasonEntry: stale,
            seasonBoard: [stale]
        )
        #expect(unloaded.weekLabel == "This week")
        #expect(unloaded.stage == nil)
        #expect(unloaded.week.recordText == "\u{2014}")
        #expect(unloaded.week.rankText == "\u{2014}")
        #expect(unloaded.season.recordText == "6\u{2013}2")
        #expect(unloaded.season.rankText == "#1")

        let missing = HomeLeagueStatus.make(
            leagueName: "Saturday",
            weekNumber: 11,
            weekStatus: .picking,
            weeklyEntry: nil,
            weeklyBoard: [],
            seasonEntry: nil,
            seasonBoard: []
        )
        #expect(missing.week.recordText == "\u{2014}")
        #expect(missing.season.recordText == "\u{2014}")
        #expect(missing.season.recordText != "0\u{2013}0")
        #expect(missing.week.rankText == "\u{2014}")
        #expect(missing.season.rankText == "\u{2014}")
    }

    private func status(
        status: WeekStatus,
        skipsSelection: Bool = false,
        picksFullyLocked: Bool = false,
        progress: HomeLeagueStatus.Progress = .init(),
        weeklyWins: Int = 0,
        weeklyLosses: Int = 0,
        rank: Int = 1
    ) -> HomeLeagueStatus.Model {
        let entry = standing(
            id: "me",
            rank: rank,
            tied: false,
            weeklyWins: weeklyWins,
            weeklyLosses: weeklyLosses,
            seasonWins: 0,
            seasonLosses: 0
        )
        return HomeLeagueStatus.make(
            leagueName: "Saturday",
            weekNumber: 11,
            weekStatus: status,
            skipsSelection: skipsSelection,
            picksFullyLocked: picksFullyLocked,
            progress: progress,
            weeklyEntry: entry,
            weeklyBoard: [entry],
            seasonEntry: entry,
            seasonBoard: [entry]
        )
    }

    private func standing(
        id: String,
        rank: Int,
        tied: Bool,
        weeklyWins: Int,
        weeklyLosses: Int,
        seasonWins: Int,
        seasonLosses: Int
    ) -> StandingEntry {
        StandingEntry(
            id: id,
            displayName: id,
            avatarColorHex: "#DC2626",
            weeklyWins: weeklyWins,
            weeklyLosses: weeklyLosses,
            seasonWins: seasonWins,
            seasonLosses: seasonLosses,
            rank: rank,
            isTied: tied
        )
    }
}
