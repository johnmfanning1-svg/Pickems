import Foundation
import Testing
@testable import Pickems

struct WidgetSnapshotBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_793_318_400)

    @Test func nilWeekProducesNoExtras() {
        let extras = WidgetSnapshotBuilder.extras(
            week: nil,
            games: [],
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras == .empty)
    }

    @Test func selectionWeekKeepsFutureGamesUnlocked() {
        let kickoff = now.addingTimeInterval(86_400)
        let extras = WidgetSnapshotBuilder.extras(
            week: week(status: .selection, selectionDeadline: now.addingTimeInterval(3_600), pickDeadline: kickoff),
            games: [slate(id: "1", kickoff: kickoff)],
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.selectionsDeadline == now.addingTimeInterval(3_600))
        #expect(extras.pickemsDeadline == kickoff)
        #expect(extras.games?.first?.isLocked == false)
        #expect(extras.games?.first?.isFinal == false)
    }

    @Test func pickingWeekDropsTheSelectionDeadline() {
        let extras = WidgetSnapshotBuilder.extras(
            week: week(
                status: .picking,
                selectionDeadline: now.addingTimeInterval(3_600),
                pickDeadline: now.addingTimeInterval(7_200)
            ),
            games: [],
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.selectionsDeadline == nil)
        #expect(extras.pickemsDeadline == now.addingTimeInterval(7_200))
    }

    @Test func weekZeroSkipsTheSelectionDeadline() {
        let extras = WidgetSnapshotBuilder.extras(
            week: week(
                status: .selection,
                weekNumber: 0,
                selectionDeadline: now.addingTimeInterval(3_600),
                pickDeadline: now.addingTimeInterval(7_200)
            ),
            games: [],
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.selectionsDeadline == nil)
    }

    @Test func rollingLockSkipsTheGameThatAlreadyKicked() {
        let first = now.addingTimeInterval(-60)
        let second = now.addingTimeInterval(3_600)
        let extras = WidgetSnapshotBuilder.extras(
            week: week(
                status: .picking,
                pickDeadline: first,
                pickLockMode: .rolling,
                weekLockAt: second
            ),
            games: [
                slate(id: "thu", kickoff: first, status: .inProgress, homeScore: 7, awayScore: 3),
                slate(id: "sat", kickoff: second),
            ],
            picks: ["thu": "h"],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.rollingLock == true)
        #expect(extras.nextLockAt == second)
        #expect(extras.games?.first?.isLocked == true)
        #expect(extras.games?.last?.isLocked == false)
        #expect(extras.games?.first?.result == .pending)
    }

    @Test func straightUpResults() {
        let kickoff = now.addingTimeInterval(-3_600)
        let extras = WidgetSnapshotBuilder.extras(
            week: week(status: .locked, pickDeadline: kickoff),
            games: [
                slate(id: "win", kickoff: kickoff, status: .final, homeScore: 21, awayScore: 14),
                slate(id: "loss", kickoff: kickoff, status: .final, homeScore: 10, awayScore: 17),
                slate(id: "push", kickoff: kickoff, status: .final, homeScore: 14, awayScore: 14),
                slate(id: "none", kickoff: kickoff, status: .final, homeScore: 21, awayScore: 14),
            ],
            picks: ["win": "h", "loss": "h", "push": "h"],
            pickMode: .straightUp,
            now: now
        )
        let results = Dictionary(uniqueKeysWithValues: (extras.games ?? []).map { ($0.id, $0.result) })
        #expect(results["win"] == .win)
        #expect(results["loss"] == .loss)
        #expect(results["push"] == .push)
        #expect(results["none"] == .loss)
        #expect(extras.games?.first { $0.id == "win" }?.userPick == "H")
    }

    @Test func capsAtTwelveAndKeepsALaterLiveGame() {
        var games: [SlateGame] = (0..<12).map { index in
            slate(
                id: "final-\(index)",
                kickoff: now.addingTimeInterval(TimeInterval(index * 60)),
                status: .final,
                homeScore: 10,
                awayScore: 7
            )
        }
        games.append(slate(id: "live", kickoff: now.addingTimeInterval(50_000), status: .inProgress, homeScore: 3, awayScore: 0))
        let extras = WidgetSnapshotBuilder.extras(
            week: week(status: .picking, pickDeadline: now.addingTimeInterval(-60), pickLockMode: .rolling),
            games: games,
            picks: [:],
            pickMode: .straightUp,
            now: now
        )
        #expect(extras.games?.count == 12)
        #expect(extras.games?.contains { $0.id == "live" } == true)
    }

    private func week(
        status: WeekStatus,
        weekNumber: Int = 6,
        selectionDeadline: Date? = nil,
        pickDeadline: Date? = nil,
        pickLockMode: DeadlinePolicy? = nil,
        weekLockAt: Date? = nil
    ) -> WeekSummary {
        WeekSummary(
            id: "2026-W\(weekNumber)",
            seasonYear: 2026,
            weekNumber: weekNumber,
            status: status,
            slateSize: 2,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: pickDeadline,
            pickLockMode: pickLockMode,
            weekLockAt: weekLockAt,
            nominationCount: 0,
            selectionDeadline: selectionDeadline
        )
    }

    private func slate(
        id: String,
        kickoff: Date,
        status: SlateGame.GameStatus = .scheduled,
        homeScore: Int? = nil,
        awayScore: Int? = nil
    ) -> SlateGame {
        SlateGame(
            id: id,
            espnEventId: id,
            homeTeamId: "h",
            homeTeamName: "Home",
            homeTeamAbbreviation: "H",
            homeTeamLogoURL: nil,
            awayTeamId: "a",
            awayTeamName: "Away",
            awayTeamAbbreviation: "A",
            awayTeamLogoURL: nil,
            spread: 3,
            spreadTeamId: "h",
            kickoff: kickoff,
            status: status,
            homeScore: homeScore,
            awayScore: awayScore,
            winnerTeamId: nil
        )
    }
}
