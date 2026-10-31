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
