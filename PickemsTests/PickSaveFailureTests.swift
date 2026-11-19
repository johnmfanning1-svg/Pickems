import Foundation
import FirebaseFirestore
import Testing
@testable import Pickems

@MainActor
struct PickSaveFailureTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func failedSaveRevertsDraftToServerPicks() {
        let vm = PicksViewModel()
        let attempted = ["game-1": "team-a", "game-2": "team-b"]
        vm.draftPicks = attempted
        vm.confidenceGameId = "game-2"
        vm.markPendingWrite(attempted, inFlight: true)

        let reverted = vm.revertFailedWrite(
            attempted,
            serverPicks: ["game-1": "team-a"],
            serverConfidenceGameId: nil
        )

        #expect(reverted)
        #expect(vm.draftPicks == ["game-1": "team-a"])
        #expect(vm.confidenceGameId == nil)
    }

    @Test func failedSaveKeepsDraftWhenNewerSaveIsPending() {
        let vm = PicksViewModel()
        let newer = ["game-1": "team-a", "game-2": "team-b", "game-3": "team-c"]
        vm.draftPicks = newer
        vm.markPendingWrite(newer, inFlight: true)

        let reverted = vm.revertFailedWrite(
            ["game-1": "team-a", "game-2": "team-b"],
            serverPicks: nil,
            serverConfidenceGameId: nil
        )

        #expect(!reverted)
        #expect(vm.draftPicks == newer)
    }

    @Test func failedSaveWithNoServerDocClearsDraft() {
        let vm = PicksViewModel()
        let attempted = ["game-1": "team-a"]
        vm.draftPicks = attempted
        vm.markPendingWrite(attempted, inFlight: true)

        vm.revertFailedWrite(attempted, serverPicks: nil, serverConfidenceGameId: nil)

        #expect(vm.draftPicks.isEmpty)
    }

    @Test func pickWritePermissionDenialSaysGameKickedOff() {
        let error = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        #expect(UserFacingError.message(for: error, context: .pickWriteStartedGame)
                == "This game already kicked off; pick not saved.")
        #expect(UserFacingError.message(for: error, context: .write)
                == "You don't have permission to do that in this league.")
    }

    @Test func pickWriteOtherFailuresSayPickDidNotSave() {
        let error = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.unavailable.rawValue)
        #expect(UserFacingError.message(for: error, context: .pickWrite) == "Pick didn't save. Try again.")
    }

    @Test func pickWriteKeepsPickErrorCopy() {
        let error = PickService.PickError.deadlinePassed
        #expect(UserFacingError.message(for: error, context: .pickWrite) == error.errorDescription)
    }

    @Test func firstSaveDropsStartedGamesOnly() {
        let games = [
            slate(id: "started", kickoff: now.addingTimeInterval(-60)),
            slate(id: "live", kickoff: now.addingTimeInterval(3_600), status: .inProgress),
            slate(id: "open", kickoff: now.addingTimeInterval(3_600)),
        ]
        let picks = ["started": "h", "live": "a", "open": "h"]

        let kept = PickService.droppingStartedGames(picks, games: games, week: rollingWeek(), now: now)

        #expect(kept == ["open": "h"])
    }

    @Test func firstSaveKeepsEveryPickBeforeKickoff() {
        let games = [
            slate(id: "g1", kickoff: now.addingTimeInterval(60)),
            slate(id: "g2", kickoff: now.addingTimeInterval(7_200)),
        ]
        let picks = ["g1": "h", "g2": "a"]

        #expect(PickService.droppingStartedGames(picks, games: games, week: rollingWeek(), now: now) == picks)
    }

    @Test func pickWritePermissionDenialWithoutStartedGameSaysPickDidNotSave() {
        let error = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        #expect(UserFacingError.message(for: error, context: .pickWrite) == "Pick didn't save. Try again.")
    }

    @Test func pickWriteContextBlamesKickoffWhenAttemptHasStartedGame() {
        let games = [
            slate(id: "started", kickoff: now.addingTimeInterval(-60)),
            slate(id: "open", kickoff: now.addingTimeInterval(3_600)),
        ]
        let context = PicksViewModel.pickWriteErrorContext(
            attempted: ["started": "h", "open": "a"],
            games: games,
            week: rollingWeek(),
            now: now
        )
        #expect(context == .pickWriteStartedGame)
    }

    @Test func pickWriteContextStaysGenericWhenNoPickedGameStarted() {
        let games = [
            slate(id: "started", kickoff: now.addingTimeInterval(-60)),
            slate(id: "open", kickoff: now.addingTimeInterval(3_600)),
        ]
        let context = PicksViewModel.pickWriteErrorContext(
            attempted: ["open": "a"],
            games: games,
            week: rollingWeek(),
            now: now
        )
        #expect(context == .pickWrite)
    }

    @Test func lateRollbackSnapshotCannotRestoreFailedPicks() {
        let vm = PicksViewModel()
        let server = ["game-1": "team-a"]
        let attempted = ["game-1": "team-a", "game-2": "team-b"]
        vm.draftPicks = attempted
        vm.markPendingWrite(attempted, inFlight: true)

        // Catch runs first, using the server-confirmed copy.
        vm.revertFailedWrite(attempted, serverPicks: server, serverConfidenceGameId: nil)
        #expect(vm.draftPicks == server)

        // The rolled-back snapshot lands afterwards.
        vm.syncDraftFromServer(server, confidenceGameId: nil)
        #expect(vm.draftPicks == server)
    }

    @Test func lateRollbackSnapshotResyncsDraftAfterRevert() {
        let vm = PicksViewModel()
        let server = ["game-1": "team-a"]
        let attempted = ["game-1": "team-a", "game-2": "team-b"]
        vm.draftPicks = attempted
        vm.markPendingWrite(attempted, inFlight: true)

        // Worst case: the revert only saw the optimistic copy.
        vm.revertFailedWrite(attempted, serverPicks: attempted, serverConfidenceGameId: nil)
        // The pending write is cleared, so the late rollback snapshot wins.
        vm.syncDraftFromServer(server, confidenceGameId: nil)
        #expect(vm.draftPicks == server)
    }

    @Test func confirmedPickIgnoresSnapshotsWithPendingWrites() {
        let confirmed = pick(["game-1": "team-a"])
        let optimistic = pick(["game-1": "team-a", "game-2": "team-b"])
        #expect(PickService.confirmedPick(current: confirmed, snapshotPick: optimistic, hasPendingWrites: true)
                == confirmed)
    }

    @Test func confirmedPickTakesServerSnapshot() {
        let confirmed = pick(["game-1": "team-a"])
        let server = pick(["game-1": "team-a", "game-2": "team-b"])
        #expect(PickService.confirmedPick(current: confirmed, snapshotPick: server, hasPendingWrites: false)
                == server)
        #expect(PickService.confirmedPick(current: confirmed, snapshotPick: nil, hasPendingWrites: false) == nil)
    }

    @Test func skippedStartedGamesSettleDraftOnSavedPicks() {
        let vm = PicksViewModel()
        let attempted = ["started": "h", "open": "a"]
        vm.draftPicks = attempted
        vm.markPendingWrite(attempted, inFlight: true)

        let settled = vm.applySkippedStartedGames(["started"], attempted: attempted, saved: pick(["open": "a"]))

        #expect(settled)
        #expect(vm.draftPicks == ["open": "a"])
        // Pending is cleared, so the next server snapshot applies normally.
        vm.syncDraftFromServer(["open": "h"], confidenceGameId: nil)
        #expect(vm.draftPicks == ["open": "h"])
    }

    @Test func nothingSkippedLeavesPendingDraftAlone() {
        let vm = PicksViewModel()
        let attempted = ["open": "a"]
        vm.draftPicks = attempted
        vm.markPendingWrite(attempted, inFlight: true)

        #expect(!vm.applySkippedStartedGames([], attempted: attempted, saved: pick(attempted)))
        #expect(vm.draftPicks == attempted)
    }

    private func pick(_ picks: [String: String]) -> UserPick {
        UserPick(id: "me", userId: "me", displayName: "Me", picks: picks, submittedAt: nil, isLocked: false)
    }

    private func rollingWeek() -> WeekSummary {
        WeekSummary(
            id: "2026-W11",
            seasonYear: 2026,
            weekNumber: 11,
            status: .picking,
            slateSize: 3,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: now.addingTimeInterval(-3_600),
            pickLockMode: .rolling,
            weekLockAt: now.addingTimeInterval(86_400),
            nominationCount: 0,
            selectionDeadline: nil
        )
    }

    private func slate(id: String, kickoff: Date, status: SlateGame.GameStatus = .scheduled) -> SlateGame {
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
            homeScore: nil,
            awayScore: nil,
            winnerTeamId: nil
        )
    }
}
