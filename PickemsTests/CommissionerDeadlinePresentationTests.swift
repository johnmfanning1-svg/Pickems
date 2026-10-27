import Foundation
import Testing
@testable import Pickems

/// 3.6.6: Set Selection Deadline opened "No Active Week" for the current week
/// and the next week. The sheet item carried no week, and a sibling edit set
/// in the same tap was still nil when `sheet(item:)` presented.
struct CommissionerDeadlinePresentationTests {
    private let league = "league"

    @Test func selectionSheetUsesCarouselWeekWhenSiblingEditIsNil() throws {
        let wrong = SelectionDeadlineEdit(
            capture: DeadlineEditCapture(
                groupId: "other",
                weekId: "2026-W1",
                weekLabel: "Season 2026 | Week 1",
                isRollingLock: false
            ),
            initialDeadline: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for (id, number) in [("2026-W8", 8), ("2026-W9", 9)] {
            let carousel = week(id: id, number: number, status: .selection)
            let route = try #require(CommissionerDeadlinePresentation.route(
                for: .selectionDeadline(carousel),
                settingsGroupId: league,
                selectedGroupId: league
            ))
            let fromNilSibling = try #require(
                CommissionerDeadlinePresentation.presentedSelectionEdit(on: route, siblingEdit: nil)
            )
            let fromWrongSibling = try #require(
                CommissionerDeadlinePresentation.presentedSelectionEdit(on: route, siblingEdit: wrong)
            )
            #expect(fromNilSibling.capture.weekId == id)
            #expect(fromNilSibling.capture.groupId == league)
            #expect(fromNilSibling.capture.weekLabel == carousel.displayLabel)
            #expect(fromNilSibling.initialDeadline == nil)
            #expect(fromWrongSibling.capture.weekId == id)
            #expect(fromWrongSibling.capture.groupId == league)
            #expect(route.id == "selectionDeadline")
        }
    }

    @Test func pickSheetUsesCarouselWeekWhenSiblingEditIsNil() throws {
        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        let carousel = week(id: "2026-W8", number: 8, status: .picking, pickDeadline: deadline)
        let wrong = PickDeadlineEdit(
            capture: DeadlineEditCapture(
                groupId: "other",
                weekId: "2026-W1",
                weekLabel: "Season 2026 | Week 1",
                isRollingLock: true
            ),
            weekStatus: .selection,
            initialDeadline: nil,
            isPastDeadline: false
        )
        let route = try #require(CommissionerDeadlinePresentation.route(
            for: .pickDeadline(carousel),
            settingsGroupId: league,
            selectedGroupId: league
        ))
        let shown = try #require(
            CommissionerDeadlinePresentation.presentedPickEdit(on: route, siblingEdit: nil)
        )
        let ignored = try #require(
            CommissionerDeadlinePresentation.presentedPickEdit(on: route, siblingEdit: wrong)
        )
        #expect(shown.capture.weekId == "2026-W8")
        #expect(shown.capture.groupId == league)
        #expect(shown.initialDeadline == deadline)
        #expect(shown.weekStatus == .picking)
        #expect(!shown.capture.isRollingLock)
        #expect(ignored.capture.weekId == "2026-W8")
        #expect(route.id == "pickDeadline")
    }

    @Test func rollingPickSheetKeepsTheCarouselWeeksRemainingLock() throws {
        let remaining = Date(timeIntervalSince1970: 1_800_100_000)
        let carousel = week(
            id: "2026-W9",
            number: 9,
            status: .picking,
            remainingLockAt: remaining,
            rolling: true
        )
        let route = try #require(CommissionerDeadlinePresentation.route(
            for: .pickDeadline(carousel),
            settingsGroupId: league,
            selectedGroupId: league
        ))
        let shown = try #require(
            CommissionerDeadlinePresentation.presentedPickEdit(on: route, siblingEdit: nil)
        )
        #expect(shown.capture.weekId == "2026-W9")
        #expect(shown.capture.isRollingLock)
        #expect(shown.initialDeadline == remaining)
        #expect(!shown.isPastDeadline)
    }

    @Test func anotherLeagueOrNoLeagueDoesNotOpenTheDeadlineSheet() {
        let carousel = week(id: "2026-W8", number: 8, status: .selection)
        let requests: [CommissionerSheetRequest] = [
            .selectionDeadline(carousel),
            .pickDeadline(carousel),
            .selections(carousel),
            .slate(carousel),
            .adminGameBrowse(carousel),
            .rankTies(TieRankDraft(entries: [member("a")]), carousel)
        ]
        for request in requests {
            #expect(CommissionerDeadlinePresentation.route(
                for: request,
                settingsGroupId: league,
                selectedGroupId: "other"
            ) == nil)
            #expect(CommissionerDeadlinePresentation.route(
                for: request,
                settingsGroupId: league,
                selectedGroupId: nil
            ) == nil)
        }
        #expect(CommissionerDeadlinePresentation.route(
            for: .members,
            settingsGroupId: league,
            selectedGroupId: nil
        ) == CommissionerSheet.members)
    }

    @Test func sheetIdentityIgnoresTheWeekPayload() throws {
        let current = week(id: "2026-W8", number: 8, status: .selection)
        let future = week(id: "2026-W9", number: 9, status: .selection)
        let currentRoute = try #require(CommissionerDeadlinePresentation.route(
            for: .selectionDeadline(current),
            settingsGroupId: league,
            selectedGroupId: league
        ))
        let futureRoute = try #require(CommissionerDeadlinePresentation.route(
            for: .selectionDeadline(future),
            settingsGroupId: league,
            selectedGroupId: league
        ))
        #expect(currentRoute.id == futureRoute.id)
        #expect(currentRoute != futureRoute)
        let currentEdit = try #require(
            CommissionerDeadlinePresentation.presentedSelectionEdit(on: currentRoute, siblingEdit: nil)
        )
        let futureEdit = try #require(
            CommissionerDeadlinePresentation.presentedSelectionEdit(on: futureRoute, siblingEdit: nil)
        )
        #expect(currentEdit.capture.weekId == "2026-W8")
        #expect(futureEdit.capture.weekId == "2026-W9")
    }

    @Test func pendingSelectionReminderUsesThePushedWeek() throws {
        let unloaded = CommissionerDeadlinePresentation.pendingSelection(
            settingsGroupId: league,
            weekId: "2026-W9",
            displayedWeek: nil
        )
        let unloadedEdit = try #require(
            CommissionerDeadlinePresentation.presentedSelectionEdit(on: unloaded, siblingEdit: nil)
        )
        #expect(unloadedEdit.capture.weekId == "2026-W9")
        #expect(unloadedEdit.capture.groupId == league)
        #expect(unloadedEdit.capture.weekLabel == "This week")
        #expect(unloadedEdit.initialDeadline == nil)

        let deadline = Date(timeIntervalSince1970: 1_800_200_000)
        let future = week(id: "2026-W9", number: 9, status: .selection, selectionDeadline: deadline)
        let loaded = CommissionerDeadlinePresentation.pendingSelection(
            settingsGroupId: league,
            weekId: future.id,
            displayedWeek: future
        )
        let loadedEdit = try #require(
            CommissionerDeadlinePresentation.presentedSelectionEdit(on: loaded, siblingEdit: nil)
        )
        #expect(loadedEdit.capture.weekId == "2026-W9")
        #expect(loadedEdit.capture.weekLabel == future.displayLabel)
        #expect(loadedEdit.initialDeadline == deadline)
    }

    @Test func selectionsSlateAndRankTiesCarryTheCarouselWeek() throws {
        let carousel = week(id: "2026-W9", number: 9, status: .scored)
        let selections = try #require(CommissionerDeadlinePresentation.route(
            for: .selections(carousel),
            settingsGroupId: league,
            selectedGroupId: league
        ))
        guard case .selections(let selectionsWeek) = selections else {
            Issue.record("Selections sheet did not receive the carousel week")
            return
        }
        #expect(selectionsWeek.id == "2026-W9")
        #expect(selections.id == "selections")

        let slate = try #require(CommissionerDeadlinePresentation.route(
            for: .slate(carousel),
            settingsGroupId: league,
            selectedGroupId: league
        ))
        guard case .slate(let slateWeek) = slate else {
            Issue.record("Slate sheet did not receive the carousel week")
            return
        }
        #expect(slateWeek.id == "2026-W9")
        #expect(slate.id == "slate")

        let amy = member("a")
        let bo = member("b")
        let ties = try #require(CommissionerDeadlinePresentation.route(
            for: .rankTies(TieRankDraft(entries: [bo, amy]), carousel),
            settingsGroupId: league,
            selectedGroupId: league
        ))
        guard case .rankTies(_, let capture) = ties else {
            Issue.record("Tie sheet did not receive the carousel week")
            return
        }
        #expect(capture.weekId == "2026-W9")
        #expect(capture.groupId == league)
        #expect(capture.weekLabel == carousel.displayLabel)
        #expect(ties.id == "rankTies.a|b")
    }

    private func week(
        id: String,
        number: Int,
        status: WeekStatus,
        selectionDeadline: Date? = nil,
        pickDeadline: Date? = nil,
        remainingLockAt: Date? = nil,
        rolling: Bool = false
    ) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: 2026,
            weekNumber: number,
            status: status,
            slateSize: 8,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: pickDeadline,
            pickLockMode: rolling ? .rolling : .firstKickoff,
            remainingLockAt: remainingLockAt,
            nominationCount: 0,
            selectionDeadline: selectionDeadline
        )
    }

    private func member(_ id: String) -> StandingEntry {
        StandingEntry(
            id: id,
            displayName: id,
            avatarColorHex: "#111111",
            weeklyWins: 1,
            weeklyLosses: 0,
            seasonWins: 1,
            seasonLosses: 0,
            rank: 1,
            isTied: true
        )
    }
}
