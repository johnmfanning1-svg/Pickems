import Foundation
import Testing
@testable import Pickems

struct CommissionerPinFollowupTests {
    @Test func remainingSelectionSlotsIsNilWhenObservingAnotherLeague() {
        let pinned = league(id: "pinned", members: 4, selectionsPerMember: 3)
        #expect(
            CommissionerPinnedLeague.remainingSelectionSlots(
                pinnedGroupId: "pinned",
                observingGroupId: "other",
                nominations: [nomination("e1")],
                slate: [],
                group: pinned,
                weekSlateSize: 9
            ) == nil
        )
        #expect(
            CommissionerPinnedLeague.remainingSelectionSlots(
                pinnedGroupId: "pinned",
                observingGroupId: nil,
                nominations: [nomination("e1")],
                slate: [],
                group: pinned,
                weekSlateSize: 9
            ) == nil
        )
    }

    @Test func remainingSelectionSlotsIsNilWhenTheGroupIsNotThePin() {
        let other = league(id: "other", members: 4, selectionsPerMember: 3)
        #expect(
            CommissionerPinnedLeague.remainingSelectionSlots(
                pinnedGroupId: "pinned",
                observingGroupId: "pinned",
                nominations: [nomination("e1")],
                slate: [],
                group: other,
                weekSlateSize: 9
            ) == nil
        )
        #expect(
            CommissionerPinnedLeague.remainingSelectionSlots(
                pinnedGroupId: "pinned",
                observingGroupId: "pinned",
                nominations: [nomination("e1")],
                slate: [],
                group: nil,
                weekSlateSize: 9
            ) == nil
        )
    }

    @Test func remainingSelectionSlotsCountsThePinnedLeague() {
        // 4 members × 3 Selections = 12. A stale week snapshot of 9 must not
        // hide the three slots the rules still have. e8 is on both lists.
        let pinned = league(id: "pinned", members: 4, selectionsPerMember: 3)
        let nominations = (1...8).map { nomination("e\($0)") }
        let slate = [game(id: "e8"), game(id: "e9")]
        let remaining = CommissionerPinnedLeague.remainingSelectionSlots(
            pinnedGroupId: "pinned",
            observingGroupId: "pinned",
            nominations: nominations,
            slate: slate,
            group: pinned,
            weekSlateSize: 9
        )
        #expect(remaining == 3)
    }

    @Test func remainingSelectionSlotsIsZeroWhenFull() {
        let pinned = league(id: "pinned", members: 4, selectionsPerMember: 3)
        let nominations = (1...12).map { nomination("e\($0)") }
        let remaining = CommissionerPinnedLeague.remainingSelectionSlots(
            pinnedGroupId: "pinned",
            observingGroupId: "pinned",
            nominations: nominations,
            slate: [],
            group: pinned,
            weekSlateSize: 9
        )
        #expect(remaining == 0)
    }

    @Test func anotherLeaguesNominationsNeverChangeRemainingSlots() {
        let pinned = league(id: "pinned", members: 4, selectionsPerMember: 3)
        let pinnedRemaining = CommissionerPinnedLeague.remainingSelectionSlots(
            pinnedGroupId: "pinned",
            observingGroupId: "pinned",
            nominations: [nomination("e1")],
            slate: [],
            group: pinned,
            weekSlateSize: 12
        )
        let foreign = CommissionerPinnedLeague.remainingSelectionSlots(
            pinnedGroupId: "pinned",
            observingGroupId: "other",
            nominations: (1...12).map { nomination("other-\($0)") },
            slate: (1...12).map { game(id: "other-slate-\($0)") },
            group: pinned,
            weekSlateSize: 12
        )
        #expect(pinnedRemaining == 11)
        #expect(foreign == nil)
    }

    @Test func openWeekSnapshotCapturesPinnedCountAndFallback() {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let second = Date(timeIntervalSince1970: 1_800_086_400)
        let slateKick = Date(timeIntervalSince1970: 1_800_172_800)
        let nominations = [
            nomination("e1", kickoff: first),
            nomination("e2", kickoff: second),
        ]
        let slate = [game(id: "game-doc", espnEventId: "e9", kickoff: slateKick)]
        let snapshot = PickService.openWeekSnapshot(
            observingGroupId: "pinned",
            groupId: "pinned",
            nominations: nominations,
            slate: slate
        )
        #expect(snapshot.count == 2)
        #expect(snapshot.fallback.map { $0.id } == ["e1", "e2", "game-doc"])
        #expect(snapshot.fallback.map { $0.kickoff } == [first, second, slateKick])
    }

    @Test func openWeekSnapshotIsEmptyWhenListenersAreElsewhere() {
        let nominations = [nomination("e1"), nomination("e2")]
        let slate = [game(id: "game-doc", espnEventId: "e9")]
        let observers: [String?] = ["other", nil]
        for observing in observers {
            let snapshot = PickService.openWeekSnapshot(
                observingGroupId: observing,
                groupId: "pinned",
                nominations: nominations,
                slate: slate
            )
            #expect(snapshot.count == nil)
            #expect(snapshot.fallback.isEmpty)
        }
    }

    @Test func activeChipFallsBackOnlyToThePinnedWeek() {
        // `week` is nil when currentWeekGroupId belongs to another league, so
        // the chip fallback is nil instead of that league's week id.
        #expect(CommissionerPinnedLeague.activeChipWeekId(espnWeekId: nil, pinnedWeekId: nil) == nil)
        #expect(
            CommissionerPinnedLeague.activeChipWeekId(espnWeekId: nil, pinnedWeekId: "2026-W7")
                == "2026-W7"
        )
        #expect(
            CommissionerPinnedLeague.activeChipWeekId(espnWeekId: "2026-W8", pinnedWeekId: "2026-W7")
                == "2026-W8"
        )
        #expect(
            CommissionerPinnedLeague.activeChipWeekId(espnWeekId: "2026-W8", pinnedWeekId: nil)
                == "2026-W8"
        )
    }

    private func league(id: String, members: Int, selectionsPerMember: Int) -> PickemGroup {
        let rules = GroupRules(
            selectionMode: .member,
            selectionsPerMember: selectionsPerMember,
            slateSize: 12,
            pickDeadline: .firstKickoff,
            tieBreaker: .commissionerOverride
        )
        return PickemGroup(
            id: id,
            name: id,
            inviteCode: "code",
            commissionerId: "commissioner",
            memberIds: (0..<members).map { "member-\($0)" },
            rules: rules,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func nomination(
        _ event: String,
        kickoff: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> Nomination {
        Nomination(
            id: event,
            submittedBy: "member",
            submitterName: "Member",
            espnEventId: event,
            spread: 3.5,
            spreadTeamId: "home",
            homeTeamId: "home",
            homeTeamName: "Home",
            awayTeamId: "away",
            awayTeamName: "Away",
            kickoff: kickoff,
            createdAt: Date(timeIntervalSince1970: 1_799_000_000)
        )
    }

    private func game(
        id: String,
        espnEventId: String? = nil,
        kickoff: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> SlateGame {
        SlateGame(
            id: id,
            espnEventId: espnEventId ?? id,
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
            status: .scheduled
        )
    }
}
