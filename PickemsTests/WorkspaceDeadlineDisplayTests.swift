import Foundation
import Testing
@testable import Pickems

struct WorkspaceDeadlineDisplayTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func bothTabsShowSelectionAndPickemsDeadlines() {
        let selectionDue = now.addingTimeInterval(3600)
        let pickLock = now.addingTimeInterval(7200)
        let week = week(
            status: .selection,
            pickDeadline: pickLock,
            selectionDeadline: selectionDue
        )

        for kind in [WorkspaceDeadlineKind.selections, .pickems] {
            let snapshot = WorkspaceDeadlineDisplay.snapshot(
                kind: kind,
                week: week,
                isCommissioner: false,
                games: [],
                now: now
            )
            #expect(snapshot.selectionDeadline == selectionDue)
            #expect(snapshot.pickemsDeadline == pickLock)
            #expect(snapshot.hasContent)
            #expect(!snapshot.showSetSelectionDeadlinePrompt)
        }
    }

    @Test func pickemsDeadlineStaysVisibleAfterLock() {
        let lock = now.addingTimeInterval(-60)
        let week = week(status: .locked, pickDeadline: lock)
        let snapshot = WorkspaceDeadlineDisplay.snapshot(
            kind: .pickems,
            week: week,
            isCommissioner: false,
            games: [],
            now: now
        )
        #expect(snapshot.pickemsDeadline == lock)
        #expect(snapshot.selectionDeadline == nil)
        #expect(snapshot.hasContent)
    }

    @Test func weekZeroHidesSelectionDeadline() {
        let week = week(
            status: .picking,
            weekNumber: 0,
            pickDeadline: now.addingTimeInterval(3600),
            selectionDeadline: now.addingTimeInterval(1800),
            slateSource: CFBWeekCalendar.weekZeroSlateSource
        )
        let snapshot = WorkspaceDeadlineDisplay.snapshot(
            kind: .selections,
            week: week,
            isCommissioner: true,
            games: [],
            now: now
        )
        #expect(week.skipsSelection)
        #expect(snapshot.selectionDeadline == nil)
        #expect(snapshot.pickemsDeadline == week.pickDeadline)
        #expect(!snapshot.showSetSelectionDeadlinePrompt)
    }

    @Test func commissionerPromptOnlyOnSelectionsWithoutDeadline() {
        let week = week(status: .selection)
        let selections = WorkspaceDeadlineDisplay.snapshot(
            kind: .selections,
            week: week,
            isCommissioner: true,
            games: [],
            now: now
        )
        let pickems = WorkspaceDeadlineDisplay.snapshot(
            kind: .pickems,
            week: week,
            isCommissioner: true,
            games: [],
            now: now
        )
        let member = WorkspaceDeadlineDisplay.snapshot(
            kind: .selections,
            week: week,
            isCommissioner: false,
            games: [],
            now: now
        )
        #expect(selections.showSetSelectionDeadlinePrompt)
        #expect(selections.hasContent)
        #expect(!pickems.showSetSelectionDeadlinePrompt)
        #expect(!pickems.hasContent)
        #expect(!member.showSetSelectionDeadlinePrompt)
        #expect(!member.hasContent)
    }

    @Test func rollingSelectionUsesFirstKickoffNotLast() {
        let first = now.addingTimeInterval(3600)
        let last = now.addingTimeInterval(48 * 3600)
        let week = week(
            status: .selection,
            pickDeadline: first,
            pickLockMode: .rolling,
            weekLockAt: last
        )
        let games = [game(id: "thu", kickoff: first), game(id: "sun", kickoff: last)]
        let snapshot = WorkspaceDeadlineDisplay.snapshot(
            kind: .pickems,
            week: week,
            isCommissioner: false,
            games: games,
            now: now
        )
        #expect(snapshot.pickemsDeadline == first)
        #expect(!snapshot.isRolling)
    }

    @Test func rollingPickingAdvancesToNextOpenKickoff() {
        let first = now.addingTimeInterval(-60)
        let last = now.addingTimeInterval(3600)
        let week = week(
            status: .picking,
            pickDeadline: first,
            pickLockMode: .rolling,
            weekLockAt: last
        )
        let games = [
            game(id: "thu", kickoff: first, status: .inProgress),
            game(id: "sun", kickoff: last),
        ]
        let snapshot = WorkspaceDeadlineDisplay.snapshot(
            kind: .pickems,
            week: week,
            isCommissioner: false,
            games: games,
            now: now
        )
        #expect(snapshot.pickemsDeadline == last)
        #expect(snapshot.isRolling)
        #expect(snapshot.openCount == 1)
        #expect(snapshot.totalCount == 2)
    }

    @Test func scoredWeekStillShowsBothDeadlines() {
        let selectionDue = now.addingTimeInterval(-48 * 3600)
        let pickLock = now.addingTimeInterval(-24 * 3600)
        let week = week(
            status: .scored,
            pickDeadline: pickLock,
            selectionDeadline: selectionDue
        )
        let snapshot = WorkspaceDeadlineDisplay.snapshot(
            kind: .selections,
            week: week,
            isCommissioner: false,
            games: [],
            now: now
        )
        #expect(snapshot.selectionDeadline == selectionDue)
        #expect(snapshot.pickemsDeadline == pickLock)
        #expect(!snapshot.isRolling)
        #expect(snapshot.hasContent)
    }

    private func week(
        status: WeekStatus,
        weekNumber: Int = 1,
        pickDeadline: Date? = nil,
        selectionDeadline: Date? = nil,
        pickLockMode: DeadlinePolicy? = nil,
        weekLockAt: Date? = nil,
        slateSource: String? = nil
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
            nominationCount: 2,
            selectionDeadline: selectionDeadline,
            slateSource: slateSource
        )
    }

    private func game(
        id: String,
        kickoff: Date,
        status: SlateGame.GameStatus = .scheduled
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
            status: status
        )
    }
}
