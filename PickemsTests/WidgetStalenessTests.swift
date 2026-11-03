import Foundation
import Testing
@testable import Pickems

struct WidgetStalenessTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func scoreboardStaleBoundaries() {
        var fresh = scoreboard()
        fresh.updatedAt = now.addingTimeInterval(-(29 * 60))
        var stale = scoreboard()
        stale.updatedAt = now.addingTimeInterval(-(31 * 60))
        #expect(WidgetPhase.isStale(snapshot: fresh, now: now) == false)
        #expect(WidgetPhase.isStale(snapshot: stale, now: now) == true)
    }

    @Test func otherPhasesUseTheDayBoundary() {
        var freshStandings = make()
        freshStandings.updatedAt = now.addingTimeInterval(-(23 * 60 * 60))
        var staleStandings = make()
        staleStandings.updatedAt = now.addingTimeInterval(-(25 * 60 * 60))
        #expect(WidgetPhase.resolve(snapshot: freshStandings, now: now) == .standings)
        #expect(WidgetPhase.isStale(snapshot: freshStandings, now: now) == false)
        #expect(WidgetPhase.isStale(snapshot: staleStandings, now: now) == true)

        var freshDeadline = make()
        freshDeadline.pickemsDeadline = now.addingTimeInterval(3_600)
        freshDeadline.updatedAt = now.addingTimeInterval(-(23 * 60 * 60))
        var staleDeadline = freshDeadline
        staleDeadline.updatedAt = now.addingTimeInterval(-(25 * 60 * 60))
        #expect(WidgetPhase.resolve(snapshot: freshDeadline, now: now) == .deadline(freshDeadline.pickemsDeadline!, .pickems))
        #expect(WidgetPhase.isStale(snapshot: freshDeadline, now: now) == false)
        #expect(WidgetPhase.isStale(snapshot: staleDeadline, now: now) == true)
    }

    @Test func futureUpdatedAtIsNotStale() {
        var snapshot = scoreboard()
        snapshot.updatedAt = now.addingTimeInterval(60)
        #expect(WidgetPhase.isStale(snapshot: snapshot, now: now) == false)
        #expect(WidgetPhase.isStale(snapshot: nil, now: now) == false)
    }

    @Test func preseasonTimelineUsesAtMostTwoEntries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let soon = now.addingTimeInterval(3_600)
        let near = WidgetPhase.preseasonTimeline(kickoff: soon, now: now, calendar: calendar)
        #expect(near.dates.count <= 2)
        #expect(near.dates == [now, soon])
        #expect(near.reload == soon)
        #expect(near.reload <= soon)

        let later = now.addingTimeInterval(3 * 24 * 60 * 60)
        let far = WidgetPhase.preseasonTimeline(kickoff: later, now: now, calendar: calendar)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        #expect(far.dates.count == 2)
        #expect(far.dates == [now, nextMidnight])
        #expect(far.reload == nextMidnight)
        #expect(far.reload <= later)
    }

    @Test func inlineCopyForEachPhase() {
        let deadline = now.addingTimeInterval(2 * 60 * 60 + 14 * 60)
        var snapshot = make()
        snapshot.weeklyWins = 4
        snapshot.weeklyLosses = 1
        snapshot.rank = 3
        snapshot.totalPlayers = 12
        #expect(WidgetInlineCopy.text(phase: .deadline(deadline, .pickems), snapshot: snapshot, now: now) == "Picks lock 2h 14m")
        #expect(WidgetInlineCopy.text(phase: .deadline(deadline, .selections), snapshot: snapshot, now: now) == "Selections lock 2h 14m")
        #expect(WidgetInlineCopy.text(phase: .scoreboard, snapshot: snapshot, now: now) == "Live: 4-1 this week")
        #expect(WidgetInlineCopy.text(phase: .standings, snapshot: snapshot, now: now) == "#3 of 12 · 4-1")
        #expect(WidgetInlineCopy.text(phase: .empty, snapshot: nil, now: now) == "Open Pickems")
    }

    @Test func rankDeltaAndPointsBack() {
        #expect(WidgetStandingsCopy.deltaSymbol(rank: 3, previousRank: 5) == "▲2")
        #expect(WidgetStandingsCopy.deltaSymbol(rank: 3, previousRank: 2) == "▼1")
        #expect(WidgetStandingsCopy.deltaSymbol(rank: 3, previousRank: 3) == nil)
        #expect(WidgetStandingsCopy.deltaSymbol(rank: 3, previousRank: nil) == nil)

        var snapshot = make()
        snapshot.rank = 3
        snapshot.weeklyWins = 7
        snapshot.topEntries = [
            .init(id: "1", displayName: "Alex", weeklyWins: 9, weeklyLosses: 1, seasonWins: 30, seasonLosses: 10, rank: 1)
        ]
        #expect(WidgetStandingsCopy.backOfFirst(snapshot) == "2 back of 1st")
        snapshot.rank = 1
        #expect(WidgetStandingsCopy.backOfFirst(snapshot) == nil)
    }

    @Test func pickStatusCoversLiveAndFinal() {
        let liveWin = game(id: "win", kickoff: now.addingTimeInterval(-60), away: 21, home: 17, pick: "OSU", final: false)
        let liveLoss = game(id: "loss", kickoff: now.addingTimeInterval(-60), away: 10, home: 24, pick: "OSU", final: false)
        let tied = game(id: "tie", kickoff: now.addingTimeInterval(-60), away: 14, home: 14, pick: "OSU", final: false)
        let noPick = game(id: "none", kickoff: now.addingTimeInterval(-60), away: 21, home: 17, pick: nil, final: false)
        let upcoming = game(id: "later", kickoff: now.addingTimeInterval(3_600), away: nil, home: nil, pick: "OSU", final: false)
        let finalWin = game(id: "fw", kickoff: now.addingTimeInterval(-3_600), away: 31, home: 14, pick: "OSU", final: true, result: .win)
        let finalLoss = game(id: "fl", kickoff: now.addingTimeInterval(-3_600), away: 10, home: 24, pick: "OSU", final: true, result: .loss)
        let push = game(id: "push", kickoff: now.addingTimeInterval(-3_600), away: 17, home: 17, pick: "OSU", final: true, result: .push)

        #expect(WidgetScoreboard.pickStatus(liveWin, now: now) == .winning)
        #expect(WidgetScoreboard.pickStatus(liveLoss, now: now) == .losing)
        #expect(WidgetScoreboard.pickStatus(tied, now: now) == .tied)
        #expect(WidgetScoreboard.pickStatus(noPick, now: now) == .noPick)
        #expect(WidgetScoreboard.pickStatus(upcoming, now: now) == .upcoming)
        #expect(WidgetScoreboard.pickStatus(finalWin, now: now) == .finalWin)
        #expect(WidgetScoreboard.pickStatus(finalLoss, now: now) == .finalLoss)
        #expect(WidgetScoreboard.pickStatus(push, now: now) == .push)
        #expect(WidgetPickStatus.finalWin.glyph == "✓")
        #expect(WidgetPickStatus.finalLoss.glyph == "✗")
        #expect(WidgetPickStatus.tied.glyph == "–")
    }

    @Test func scoreboardPutsLiveGamesFirstAndTruncates() {
        let liveEarly = game(id: "live-early", kickoff: now.addingTimeInterval(-200), away: 7, home: 3, pick: "OSU", final: false)
        let liveLate = game(id: "live-late", kickoff: now.addingTimeInterval(-50), away: 10, home: 21, pick: "OSU", final: false)
        let lossEarly = game(id: "loss-early", kickoff: now.addingTimeInterval(-9_000), away: 3, home: 21, pick: "OSU", final: true, result: .loss)
        let lossLate = game(id: "loss-late", kickoff: now.addingTimeInterval(-8_000), away: 7, home: 14, pick: "OSU", final: true, result: .loss)
        let win = game(id: "win", kickoff: now.addingTimeInterval(-7_000), away: 28, home: 10, pick: "OSU", final: true, result: .win)
        let next = game(id: "next", kickoff: now.addingTimeInterval(4_000), away: nil, home: nil, pick: "OSU", final: false)
        let later = game(id: "later", kickoff: now.addingTimeInterval(8_000), away: nil, home: nil, pick: nil, final: false)
        let games = [later, win, lossLate, next, liveLate, lossEarly, liveEarly]

        let three = WidgetScoreboard.ordered(games, now: now, limit: 3).map(\.id)
        let six = WidgetScoreboard.ordered(games, now: now, limit: 6).map(\.id)
        #expect(three == ["live-early", "live-late", "loss-early"])
        #expect(six == ["live-early", "live-late", "loss-early", "loss-late", "win", "next"])
    }

    @Test func sharedWidgetSourcesStayIdentical() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for name in ["StandingsSnapshot.swift", "WidgetPhase.swift"] {
            let app = try String(contentsOf: root.appendingPathComponent("Pickems/Shared/\(name)"), encoding: .utf8)
            let widget = try String(contentsOf: root.appendingPathComponent("PickemsWidget/\(name)"), encoding: .utf8)
            #expect(app == widget)
        }
    }

    private func make() -> StandingsSnapshot {
        StandingsSnapshot(
            groupId: "g",
            groupName: "Saturday Crew",
            weekNumber: 9,
            seasonYear: 2026,
            userId: "u",
            userDisplayName: "You",
            weeklyWins: 7,
            weeklyLosses: 3,
            seasonWins: 61,
            seasonLosses: 29,
            rank: 3,
            totalPlayers: 12,
            topEntries: [],
            updatedAt: now
        )
    }

    private func scoreboard() -> StandingsSnapshot {
        var snapshot = make()
        snapshot.games = [game(id: "live", kickoff: now.addingTimeInterval(-60), away: 21, home: 17, pick: "OSU", final: false)]
        return snapshot
    }

    private func game(
        id: String,
        kickoff: Date,
        away: Int?,
        home: Int?,
        pick: String?,
        final: Bool,
        result: StandingsSnapshot.SnapshotPickResult = .pending
    ) -> StandingsSnapshot.SnapshotGame {
        StandingsSnapshot.SnapshotGame(
            id: id,
            awayShortName: "OSU",
            homeShortName: "MICH",
            kickoff: kickoff,
            isLocked: kickoff <= now,
            isFinal: final,
            awayScore: away,
            homeScore: home,
            userPick: pick,
            result: result
        )
    }
}
