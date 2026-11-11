import Foundation
import Testing
@testable import Pickems

struct WidgetPhaseTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func nilSnapshotIsEmpty() {
        #expect(WidgetPhase.resolve(snapshot: nil, now: now) == .empty)
    }

    @Test func futureSeasonKickoffIsPreseason() {
        var snapshot = make()
        snapshot.seasonKickoffAt = now.addingTimeInterval(86_400)
        snapshot.selectionsDeadline = now.addingTimeInterval(3_600)
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .preseason)
    }

    @Test func pastSeasonKickoffIsNotPreseason() {
        var snapshot = make()
        snapshot.seasonKickoffAt = now.addingTimeInterval(-60)
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .standings)
    }

    @Test func selectionsDeadlineWhileNothingIsLocked() {
        var snapshot = make()
        let selections = now.addingTimeInterval(18 * 3_600)
        let pickems = now.addingTimeInterval(48 * 3_600)
        snapshot.selectionsDeadline = selections
        snapshot.pickemsDeadline = pickems
        snapshot.games = [game(kickoff: pickems)]
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .deadline(selections, .selections))
    }

    @Test func pickemsDeadlineAfterSelectionsHavePassed() {
        var snapshot = make()
        let pickems = now.addingTimeInterval(5 * 3_600)
        snapshot.selectionsDeadline = now.addingTimeInterval(-60)
        snapshot.pickemsDeadline = pickems
        snapshot.games = [game(kickoff: pickems)]
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .deadline(pickems, .pickems))
    }

    @Test func deadlineAtTheExactInstantMovesOn() {
        var snapshot = make()
        let pickems = now.addingTimeInterval(3_600)
        snapshot.selectionsDeadline = now
        snapshot.pickemsDeadline = pickems
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .deadline(pickems, .pickems))
    }

    @Test func kickoffPassedButNotMarkedLockedIsScoreboard() {
        var snapshot = make()
        snapshot.pickemsDeadline = now.addingTimeInterval(3_600)
        snapshot.games = [game(kickoff: now.addingTimeInterval(-60), locked: false, final: false)]
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .scoreboard)
    }

    @Test func kickoffAtThisInstantIsScoreboard() {
        var snapshot = make()
        snapshot.pickemsDeadline = now.addingTimeInterval(3_600)
        snapshot.games = [game(kickoff: now, locked: false, final: false)]
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .scoreboard)
    }

    @Test func rollingLockMidWeekIsScoreboard() {
        var snapshot = make()
        snapshot.rollingLock = true
        snapshot.pickemsDeadline = now.addingTimeInterval(-3_600)
        let later = now.addingTimeInterval(7_200)
        snapshot.games = [
            game(id: "thu", kickoff: now.addingTimeInterval(-3_600), locked: true, final: false),
            game(id: "sat", kickoff: later, locked: false, final: false),
        ]
        snapshot.nextLockAt = later
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .scoreboard)
        #expect(WidgetPhase.nextLockDate(snapshot: snapshot, now: now) == later)
    }

    @Test func nextLockIsNilWhenTheWeekIsNotRolling() {
        var snapshot = make()
        snapshot.rollingLock = false
        snapshot.games = [game(kickoff: now.addingTimeInterval(3_600))]
        #expect(WidgetPhase.nextLockDate(snapshot: snapshot, now: now) == nil)
    }

    @Test func allGamesFinalIsStandingsEvenWithAFutureDeadline() {
        var snapshot = make()
        snapshot.pickemsDeadline = now.addingTimeInterval(3_600)
        snapshot.weekPhaseHint = "deadline"
        snapshot.games = [
            game(id: "a", kickoff: now.addingTimeInterval(-7_200), locked: true, final: true, result: .win),
            game(id: "b", kickoff: now.addingTimeInterval(-3_600), locked: true, final: true, result: .loss),
        ]
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .standings)
    }

    @Test func missingDeadlinesFallBackToStandings() {
        var snapshot = make()
        snapshot.games = [game(kickoff: now.addingTimeInterval(86_400))]
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: now) == .standings)
        #expect(WidgetPhase.resolve(snapshot: make(), now: now) == .standings)
    }

    @Test func boundaryDatesIncludeDeadlinesAndFutureKickoffs() {
        var snapshot = make()
        let selections = now.addingTimeInterval(3_600)
        let pickems = now.addingTimeInterval(7_200)
        let kickoff = now.addingTimeInterval(10_000)
        snapshot.selectionsDeadline = selections
        snapshot.pickemsDeadline = pickems
        snapshot.games = [
            game(id: "past", kickoff: now.addingTimeInterval(-10), final: true, result: .win),
            game(id: "next", kickoff: kickoff),
        ]
        #expect(WidgetPhase.boundaryDates(snapshot: snapshot, now: now) == [selections, pickems, kickoff])
        #expect(WidgetPhase.entryDates(snapshot: snapshot, now: now).first == now)
    }

    @Test func deadlineAndStandingsTimelinesUseTheNextBoundary() {
        var deadlineSnapshot = make()
        let deadline = now.addingTimeInterval(3_600)
        let laterKickoff = now.addingTimeInterval(7_200)
        deadlineSnapshot.selectionsDeadline = deadline
        deadlineSnapshot.pickemsDeadline = laterKickoff
        deadlineSnapshot.games = [game(kickoff: laterKickoff)]
        let deadlinePhase = WidgetPhase.resolve(snapshot: deadlineSnapshot, now: now)
        let deadlineDates = WidgetPhase.timelineDates(snapshot: deadlineSnapshot, phase: deadlinePhase, now: now)
        #expect(deadlinePhase == .deadline(deadline, .selections))
        #expect(deadlineDates == [now, deadline, laterKickoff])
        #expect(WidgetPhase.reloadDate(phase: deadlinePhase, dates: deadlineDates, now: now) == deadline)

        var standingsSnapshot = make()
        let kickoff = now.addingTimeInterval(5_000)
        standingsSnapshot.games = [game(kickoff: kickoff)]
        let standingsPhase = WidgetPhase.resolve(snapshot: standingsSnapshot, now: now)
        let standingsDates = WidgetPhase.timelineDates(snapshot: standingsSnapshot, phase: standingsPhase, now: now)
        #expect(standingsPhase == .standings)
        #expect(standingsDates == [now, kickoff])
        #expect(WidgetPhase.reloadDate(phase: standingsPhase, dates: standingsDates, now: now) == kickoff)

        #expect(WidgetPhase.reloadDate(phase: .scoreboard, dates: [now, kickoff], now: now) == now.addingTimeInterval(15 * 60))
    }

    @Test func deepLinksUseExistingRoutes() {
        let snapshot = make(groupId: "league-1")
        let selections = WidgetDeepLink.url(
            phase: .deadline(now.addingTimeInterval(60), .selections),
            snapshot: snapshot
        )
        let pickems = WidgetDeepLink.url(
            phase: .deadline(now.addingTimeInterval(60), .pickems),
            snapshot: snapshot
        )
        let board = WidgetDeepLink.url(phase: .scoreboard, snapshot: snapshot)
        let standings = WidgetDeepLink.url(phase: .standings, snapshot: snapshot)

        #expect(DeepLinkRouter.parse(url: selections!) == .openSelections(groupId: "league-1"))
        #expect(DeepLinkRouter.parse(url: pickems!) == .openWeekPickems(groupId: "league-1", weekId: "2026-W6"))
        #expect(DeepLinkRouter.parse(url: board!) == .openWeekPickems(groupId: "league-1", weekId: "2026-W6"))
        #expect(DeepLinkRouter.parse(url: standings!) == .openLeaderboard(groupId: "league-1", weekId: "2026-W6"))
        #expect(WidgetDeepLink.url(phase: .preseason, snapshot: snapshot) == nil)
        #expect(WidgetDeepLink.url(phase: .empty, snapshot: nil) == nil)
    }

    @Test func oldSnapshotJSONDecodesWithoutNewFields() throws {
        let json = """
        {
          "groupId": "g",
          "groupName": "Saturday Crew",
          "weekNumber": 3,
          "seasonYear": 2026,
          "userId": "u",
          "userDisplayName": "You",
          "weeklyWins": 1,
          "weeklyLosses": 0,
          "seasonWins": 4,
          "seasonLosses": 2,
          "rank": 2,
          "totalPlayers": 8,
          "topEntries": [],
          "updatedAt": 0
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StandingsSnapshot.self, from: json)
        #expect(decoded.groupName == "Saturday Crew")
        #expect(decoded.rank == 2)
        #expect(decoded.games == nil)
        #expect(decoded.selectionsDeadline == nil)
        #expect(decoded.pickemsDeadline == nil)
        #expect(decoded.rollingLock == nil)
        #expect(decoded.nextLockAt == nil)
        #expect(decoded.weekPhaseHint == nil)
        #expect(WidgetPhase.resolve(snapshot: decoded, now: now) == .standings)
    }

    @Test func newFieldsRoundTrip() throws {
        var snapshot = make()
        snapshot.selectionsDeadline = now.addingTimeInterval(100)
        snapshot.pickemsDeadline = now.addingTimeInterval(200)
        snapshot.rollingLock = true
        snapshot.nextLockAt = now.addingTimeInterval(300)
        snapshot.weekPhaseHint = "ignored"
        snapshot.games = [game(kickoff: now.addingTimeInterval(300), result: .pending)]
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(StandingsSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test func roundTwoFieldsAreOptionalOnOldPayloads() throws {
        let json = """
        {
          "groupId": "g",
          "groupName": "Saturday Crew",
          "weekNumber": 3,
          "seasonYear": 2026,
          "userId": "u",
          "userDisplayName": "You",
          "weeklyWins": 1,
          "weeklyLosses": 0,
          "seasonWins": 4,
          "seasonLosses": 2,
          "rank": 2,
          "totalPlayers": 8,
          "topEntries": [],
          "updatedAt": 0,
          "games": [{
            "id": "g1",
            "awayShortName": "OSU",
            "homeShortName": "MICH",
            "kickoff": 0,
            "isLocked": false,
            "isFinal": false,
            "result": "pending"
          }]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StandingsSnapshot.self, from: json)
        #expect(decoded.picksMade == nil)
        #expect(decoded.picksTotal == nil)
        #expect(decoded.selectionsMade == nil)
        #expect(decoded.selectionsTotal == nil)
        #expect(decoded.selectionQuota == nil)
        #expect(decoded.previousRank == nil)
        #expect(decoded.games?.first?.awayColorHex == nil)
        #expect(decoded.games?.first?.homeColorHex == nil)
        #expect(decoded.games?.first?.statusText == nil)
        #expect(decoded.games?.first?.isUserSelection == nil)

        var roundTrip = decoded
        roundTrip.picksMade = 7
        roundTrip.picksTotal = 10
        roundTrip.previousRank = 4
        roundTrip.games?[0].awayColorHex = "#BA0C2F"
        roundTrip.games?[0].homeColorHex = "#00274C"
        roundTrip.games?[0].statusText = "Q3 4:12"
        let data = try JSONEncoder().encode(roundTrip)
        let again = try JSONDecoder().decode(StandingsSnapshot.self, from: data)
        #expect(again == roundTrip)
    }

    @Test func memberSelectionProgressListsOnlyTheUsersGames() {
        var snapshot = make()
        snapshot.selectionQuota = WidgetSelectionQuota.member
        snapshot.selectionsMade = 2
        snapshot.selectionsTotal = 2
        snapshot.picksMade = 0
        snapshot.picksTotal = 4
        snapshot.games = [
            row(id: "mine-1", kickoff: now.addingTimeInterval(3_600), selection: true),
            row(id: "mine-2", kickoff: now.addingTimeInterval(4_000), selection: true),
            row(id: "them-1", kickoff: now.addingTimeInterval(5_000), selection: false),
            row(id: "them-2", kickoff: now.addingTimeInterval(6_000), selection: false),
        ]
        let done = WidgetDeadlineProgress.model(snapshot: snapshot, kind: .selections)
        #expect(done.completionTitle == "All selections in ✓")
        #expect(done.countdownIsHero == false)
        #expect(done.showsBar == true)
        #expect(done.made == 2)
        #expect(done.total == 2)
        #expect(done.list == .userSelections)
        #expect(WidgetDeadlineProgress.rows(snapshot: snapshot, kind: .selections).map(\.id) == ["mine-1", "mine-2"])

        let afterLock = WidgetDeadlineProgress.model(snapshot: snapshot, kind: .pickems)
        #expect(afterLock.completionTitle == nil)
        #expect(afterLock.lockTitle == "Picks lock in")
        #expect(afterLock.detail == "0 of 4 picked")
        #expect(afterLock.list == .unpicked)
        #expect(WidgetDeadlineProgress.rows(snapshot: snapshot, kind: .pickems).map(\.id) == ["mine-1", "mine-2", "them-1", "them-2"])

        snapshot.selectionsMade = 0
        snapshot.games = [row(id: "them-1", kickoff: now.addingTimeInterval(5_000), selection: false)]
        let none = WidgetDeadlineProgress.model(snapshot: snapshot, kind: .selections)
        #expect(none.completionTitle == nil)
        #expect(none.detail == "0 of 2 selected")
        #expect(none.listEmpty == "Select your games")
        #expect(WidgetDeadlineProgress.rows(snapshot: snapshot, kind: .selections).isEmpty)
    }

    @Test func pickWindowProgressCountsPicksAndUnpickedGames() {
        var snapshot = make()
        snapshot.picksMade = 1
        snapshot.picksTotal = 3
        snapshot.games = [
            row(id: "picked", kickoff: now.addingTimeInterval(3_600), pick: "HOME"),
            row(id: "open-1", kickoff: now.addingTimeInterval(4_000)),
            row(id: "open-2", kickoff: now.addingTimeInterval(5_000)),
        ]
        let open = WidgetDeadlineProgress.model(snapshot: snapshot, kind: .pickems)
        #expect(open.detail == "1 of 3 picked")
        #expect(open.showsBar == true)
        #expect(open.list == .unpicked)
        #expect(WidgetDeadlineProgress.rows(snapshot: snapshot, kind: .pickems).map(\.id) == ["open-1", "open-2"])

        snapshot.picksMade = 3
        snapshot.games = [
            row(id: "a", kickoff: now.addingTimeInterval(3_600), pick: "HOME"),
            row(id: "b", kickoff: now.addingTimeInterval(4_000), pick: "HOME"),
            row(id: "c", kickoff: now.addingTimeInterval(5_000), pick: "HOME"),
        ]
        let done = WidgetDeadlineProgress.model(snapshot: snapshot, kind: .pickems)
        #expect(done.completionTitle == "All picks in ✓")
        #expect(done.countdownIsHero == false)
        #expect(done.showsBar == false)
        #expect(done.list == .none)
        #expect(WidgetDeadlineProgress.rows(snapshot: snapshot, kind: .pickems).isEmpty)
    }

    @Test func commissionerSelectionProgressWaitsOrShowsTheSlate() {
        var snapshot = make()
        snapshot.selectionQuota = WidgetSelectionQuota.commissioner
        snapshot.selectionsMade = 0
        snapshot.selectionsTotal = 8
        let waiting = WidgetDeadlineProgress.model(snapshot: snapshot, kind: .selections)
        #expect(waiting.detail == "Waiting on selections")
        #expect(waiting.showsBar == false)
        #expect(waiting.list == .none)
        #expect(waiting.completionTitle == nil)

        snapshot.selectionsMade = 8
        snapshot.games = [row(id: "slate", kickoff: now.addingTimeInterval(3_600))]
        let set = WidgetDeadlineProgress.model(snapshot: snapshot, kind: .selections)
        #expect(set.completionTitle == "Slate is set")
        #expect(set.showsBar == true)
        #expect(set.countdownIsHero == false)
        #expect(set.list == .slate)
        #expect(WidgetDeadlineProgress.rows(snapshot: snapshot, kind: .selections).map(\.id) == ["slate"])
    }

    @Test func timelineEntriesCrossSelectionAndPickLocks() {
        var snapshot = make()
        let selections = now.addingTimeInterval(3_600)
        let lock = now.addingTimeInterval(7_200)
        snapshot.selectionsDeadline = selections
        snapshot.pickemsDeadline = lock
        snapshot.games = [game(id: "kick", kickoff: lock)]
        let phase = WidgetPhase.resolve(snapshot: snapshot, now: now)
        let dates = WidgetPhase.timelineDates(snapshot: snapshot, phase: phase, now: now)
        #expect(dates == [now, selections, lock])
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: selections) == .deadline(lock, .pickems))
        #expect(WidgetPhase.resolve(snapshot: snapshot, now: lock) == .scoreboard)
    }

    @Test func livePickProgressCountsCorrectLostAndPending() {
        let games = [
            row(id: "ahead", kickoff: now.addingTimeInterval(-600), pick: "HOME", away: 10, home: 21),
            row(id: "behind", kickoff: now.addingTimeInterval(-3_600), pick: "HOME", away: 17, home: 10, final: true, result: .loss),
            row(id: "later", kickoff: now.addingTimeInterval(3_600), pick: "HOME"),
            row(id: "skipped", kickoff: now.addingTimeInterval(-600), away: 28, home: 7),
        ]
        let summary = WidgetPickProgress.summarize(games, now: now)
        #expect(summary?.correct == 1)
        #expect(summary?.lost == 1)
        #expect(summary?.pending == 1)
        #expect(summary?.line == "1 correct · 1 lost · 1 pending")

        let settled = WidgetPickProgress.summarize(
            [
                row(id: "win", kickoff: now.addingTimeInterval(-3_600), pick: "HOME", final: true, result: .win),
                row(id: "loss", kickoff: now.addingTimeInterval(-2_000), pick: "HOME", final: true, result: .loss),
            ],
            now: now
        )
        #expect(settled?.line == "1 won · 1 lost")
        #expect(WidgetPickProgress.summarize([row(id: "none", kickoff: now)], now: now) == nil)
    }

    private func row(
        id: String,
        kickoff: Date,
        pick: String? = nil,
        selection: Bool? = nil,
        away: Int? = nil,
        home: Int? = nil,
        final: Bool = false,
        result: StandingsSnapshot.SnapshotPickResult = .pending
    ) -> StandingsSnapshot.SnapshotGame {
        StandingsSnapshot.SnapshotGame(
            id: id,
            awayShortName: "AWAY",
            homeShortName: "HOME",
            kickoff: kickoff,
            isLocked: kickoff <= now,
            isFinal: final,
            awayScore: away,
            homeScore: home,
            userPick: pick,
            result: result,
            isUserSelection: selection
        )
    }

    private func make(groupId: String = "g") -> StandingsSnapshot {
        StandingsSnapshot(
            groupId: groupId,
            groupName: "Saturday Crew",
            weekNumber: 6,
            seasonYear: 2026,
            userId: "u",
            userDisplayName: "You",
            weeklyWins: 3,
            weeklyLosses: 1,
            seasonWins: 20,
            seasonLosses: 8,
            rank: 2,
            totalPlayers: 8,
            topEntries: [],
            updatedAt: now
        )
    }

    private func game(
        id: String = "g",
        kickoff: Date,
        locked: Bool = false,
        final: Bool = false,
        result: StandingsSnapshot.SnapshotPickResult = .pending
    ) -> StandingsSnapshot.SnapshotGame {
        StandingsSnapshot.SnapshotGame(
            id: id,
            awayShortName: "AWAY",
            homeShortName: "HOME",
            kickoff: kickoff,
            isLocked: locked,
            isFinal: final,
            awayScore: final ? 10 : nil,
            homeScore: final ? 17 : nil,
            userPick: "HOME",
            result: result
        )
    }
}
