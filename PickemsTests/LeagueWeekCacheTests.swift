import Foundation
import Testing
@testable import Pickems

struct LeagueWeekCacheTests {
    private let weekId = "2026-W7"
    private let ppp = "ppp"
    private let core4 = "core4"

    @Test func selectionDeadlineDoesNotCrossLeaguesThatShareAWeekId() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_000)
        var current: WeekSummary? = week(deadline: nil)
        var chips = [week(deadline: nil), week(id: "2026-W6", number: 6)]
        LeagueWeekCache.update(
            observedGroupId: core4,
            availableWeeksGroupId: core4,
            currentWeek: &current,
            availableWeeks: &chips,
            groupId: ppp,
            weekId: weekId
        ) { week in
            SelectionDeadlineLocal.apply(
                deadline: deadline,
                setAt: deadline,
                setBy: "commish",
                to: &week
            )
        }

        #expect(current?.selectionDeadline == nil)
        #expect(current?.selectionDeadlineSetBy == nil)
        #expect(chips[0].selectionDeadline == nil)
        #expect(chips[1].id == "2026-W6")
    }

    @Test func selectionDeadlineUpdatesOnlyTheOwningLeagueCaches() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_000)
        let setAt = Date(timeIntervalSince1970: 1_700_000_100)
        var current: WeekSummary? = week(deadline: nil)
        var chips = [week(deadline: nil)]
        LeagueWeekCache.update(
            observedGroupId: ppp,
            availableWeeksGroupId: ppp,
            currentWeek: &current,
            availableWeeks: &chips,
            groupId: ppp,
            weekId: weekId
        ) { week in
            SelectionDeadlineLocal.apply(deadline: deadline, setAt: setAt, setBy: "commish", to: &week)
        }

        #expect(current?.selectionDeadline == deadline)
        #expect(current?.selectionDeadlineSetAt == setAt)
        #expect(current?.selectionDeadlineSetBy == "commish")
        #expect(chips[0].selectionDeadline == deadline)
        #expect(chips[0].selectionDeadlineSetBy == "commish")
    }

    @Test func displayedWeekAndChipListCanBelongToDifferentLeagues() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_000)
        var current: WeekSummary? = week(deadline: nil)
        var chips = [week(deadline: nil)]
        // Listener has moved to Core 4, but the chip list is still PPP's.
        LeagueWeekCache.update(
            observedGroupId: core4,
            availableWeeksGroupId: ppp,
            currentWeek: &current,
            availableWeeks: &chips,
            groupId: ppp,
            weekId: weekId
        ) { week in
            SelectionDeadlineLocal.apply(deadline: deadline, setAt: deadline, setBy: "commish", to: &week)
        }

        #expect(current?.selectionDeadline == nil)
        #expect(chips[0].selectionDeadline == deadline)
    }

    @Test func clearingASelectionDeadlineDoesNotClearTheOtherLeague() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_000)
        var current: WeekSummary? = week(status: .picking, deadline: deadline, setBy: "commish")
        var chips = [week(status: .picking, deadline: deadline, setBy: "commish")]
        LeagueWeekCache.update(
            observedGroupId: core4,
            availableWeeksGroupId: core4,
            currentWeek: &current,
            availableWeeks: &chips,
            groupId: ppp,
            weekId: weekId
        ) { week in
            SelectionDeadlineLocal.clear(on: &week)
        }

        #expect(current?.status == .picking)
        #expect(current?.selectionDeadline == deadline)
        #expect(chips[0].selectionDeadline == deadline)
    }

    @Test func clearingUpdatesTheLeagueThatOwnsTheCache() {
        var current: WeekSummary? = week(status: .picking, deadline: Date())
        var chips = [week(status: .locked, deadline: Date())]
        LeagueWeekCache.update(
            observedGroupId: ppp,
            availableWeeksGroupId: ppp,
            currentWeek: &current,
            availableWeeks: &chips,
            groupId: ppp,
            weekId: weekId
        ) { week in
            SelectionDeadlineLocal.clear(on: &week)
        }

        #expect(current?.status == .selection)
        #expect(current?.selectionDeadline == nil)
        #expect(current?.lockedAt == nil)
        #expect(chips[0].status == .selection)
        #expect(chips[0].selectionDeadline == nil)
    }

    @Test func pickDeadlineUsesCapturedLockModeAndStaysInOneLeague() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_500)
        var current: WeekSummary? = week(status: .picking, rolling: true)
        var chips = [week(status: .picking, rolling: true)]
        #expect(PickDeadlineWrite.fieldName(isRollingLock: false) == "pickDeadline")

        LeagueWeekCache.update(
            observedGroupId: core4,
            availableWeeksGroupId: core4,
            currentWeek: &current,
            availableWeeks: &chips,
            groupId: ppp,
            weekId: weekId
        ) { week in
            PickDeadlineWrite.apply(deadline: deadline, isRollingLock: false, to: &week)
        }

        #expect(current?.pickDeadline == nil)
        #expect(current?.remainingLockAt == nil)
        #expect(chips[0].pickDeadline == nil)
    }

    @Test func rollingPickDeadlineSetsRemainingLockOnlyOnThatLeague() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_500)
        var current: WeekSummary? = week(status: .picking, rolling: true)
        var chips = [week(status: .picking, rolling: true)]
        #expect(PickDeadlineWrite.fieldName(isRollingLock: true) == "remainingLockAt")

        LeagueWeekCache.update(
            observedGroupId: ppp,
            availableWeeksGroupId: ppp,
            currentWeek: &current,
            availableWeeks: &chips,
            groupId: ppp,
            weekId: weekId
        ) { week in
            PickDeadlineWrite.apply(deadline: deadline, isRollingLock: true, to: &week)
        }

        #expect(current?.remainingLockAt == deadline)
        #expect(current?.pickDeadline == nil)
        #expect(chips[0].remainingLockAt == deadline)
        #expect(chips[0].pickDeadline == nil)
    }

    @Test func reopenPickemsDoesNotReopenAnotherLeaguesWeek() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_500)
        var current: WeekSummary? = week(status: .locked, rolling: false)
        var chips = [current]
        LeagueWeekCache.update(
            observedGroupId: core4,
            availableWeeksGroupId: core4,
            currentWeek: &current,
            availableWeeks: &chips,
            groupId: ppp,
            weekId: weekId
        ) { week in
            week.status = .picking
            week.lockedAt = nil
            PickDeadlineWrite.apply(deadline: deadline, isRollingLock: false, to: &week)
        }

        #expect(current?.status == .locked)
        #expect(current?.pickDeadline == nil)
        #expect(chips[0].status == .locked)
    }

    @Test func saveTargetStaysOnTheLeagueCapturedWhenTheSheetOpened() {
        let captured = DeadlineEditCapture(
            groupId: ppp,
            weekId: weekId,
            weekLabel: "Season 2026 | Week 7",
            isRollingLock: false
        )
        let sameWeekDifferentLeague = captured.writeTarget(
            selectedGroupId: core4,
            selectedWeekId: weekId
        )
        let stillSameLeague = captured.writeTarget(
            selectedGroupId: ppp,
            selectedWeekId: weekId
        )

        #expect(sameWeekDifferentLeague.groupId == ppp)
        #expect(sameWeekDifferentLeague.weekId == weekId)
        #expect(stillSameLeague.groupId == ppp)
        #expect(stillSameLeague.weekId == weekId)
    }

    @Test func mismatchedWeekIdIsNotUpdatedEvenInTheSameLeague() {
        var current: WeekSummary? = week(deadline: nil)
        var chips = [week(deadline: nil)]
        LeagueWeekCache.update(
            observedGroupId: ppp,
            availableWeeksGroupId: ppp,
            currentWeek: &current,
            availableWeeks: &chips,
            groupId: ppp,
            weekId: "2026-W8"
        ) { week in
            SelectionDeadlineLocal.apply(
                deadline: Date(),
                setAt: Date(),
                setBy: "commish",
                to: &week
            )
        }

        #expect(current?.selectionDeadline == nil)
        #expect(chips[0].selectionDeadline == nil)
    }

    private func week(
        id: String? = nil,
        number: Int = 7,
        status: WeekStatus = .selection,
        deadline: Date? = nil,
        setBy: String? = nil,
        rolling: Bool = false
    ) -> WeekSummary {
        WeekSummary(
            id: id ?? weekId,
            seasonYear: 2026,
            weekNumber: number,
            status: status,
            slateSize: 8,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: status == .locked ? Date(timeIntervalSince1970: 1_600_000_000) : nil,
            pickDeadline: nil,
            pickLockMode: rolling ? .rolling : .firstKickoff,
            weekLockAt: nil,
            remainingLockAt: nil,
            nominationCount: 0,
            selectionDeadline: deadline,
            selectionDeadlineSetAt: deadline,
            selectionDeadlineSetBy: setBy
        )
    }
}
