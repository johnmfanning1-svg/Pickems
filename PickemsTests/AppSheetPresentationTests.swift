import Foundation
import Testing
@testable import Pickems

struct AppSheetPresentationTests {
    @Test func sheetIdentitiesAreStableAndUnique() {
        #expect(AppSheet.gameBrowse.id == AppSheet.gameBrowse.id)
        #expect(AppSheet.joinGroup.id != AppSheet.gameBrowse.id)
        #expect(AppSheet.createLeague.id != AppSheet.commissionerSettings.id)
        #expect(AppSheet.notificationSettings.id == "notificationSettings")
        #expect(AppSheet.notificationSettings.id != AppSheet.editProfile.id)
        #expect(
            AppSheet.favoriteTeam(isOnboardingPrompt: true).id
                != AppSheet.favoriteTeam(isOnboardingPrompt: false).id
        )
        #expect(
            AppSheet.coverMoment(
                gameLabel: "ALA @ AUB",
                resultTitle: "Covered",
                recordText: "1-0 today",
                rankText: "You're #1 live"
            ).id
                == AppSheet.coverMoment(
                    gameLabel: "ALA @ AUB",
                    resultTitle: "Covered",
                    recordText: "2-0 today",
                    rankText: "You're #1 live"
                ).id
        )
    }

    @Test func replacePolicyAlwaysShowsIncomingSheet() {
        let next = AppSheetRouting.nextPresented(
            current: .joinGroup,
            incoming: .gameBrowse,
            policy: .replace
        )
        #expect(next == .gameBrowse)
    }

    @Test func idlePolicyKeepsAnOpenSheet() {
        let kept = AppSheetRouting.nextPresented(
            current: .joinGroup,
            incoming: .stayOnTime,
            policy: .ifIdle
        )
        #expect(kept == .joinGroup)

        let presented = AppSheetRouting.nextPresented(
            current: nil,
            incoming: .stayOnTime,
            policy: .ifIdle
        )
        #expect(presented == .stayOnTime)
    }

    @Test func takenIdsIncludeSlateAndNominations() {
        let ids = GameBrowseTakenIds.make(
            nominationEventIds: ["e1", "e2"],
            slateEventIds: ["e2", "e3"]
        )
        #expect(ids == ["e1", "e2", "e3"])
    }

    @Test func commissionerSheetIdentitiesAreStableAndUnique() {
        let week8 = commissionerWeek(id: "2026-W8", number: 8)
        let week9 = commissionerWeek(id: "2026-W9", number: 9)
        let selection8 = CommissionerDeadlinePresentation.selectionEdit(settingsGroupId: "league", week: week8)
        let selection9 = CommissionerDeadlinePresentation.selectionEdit(settingsGroupId: "league", week: week9)
        let pick8 = CommissionerDeadlinePresentation.pickEdit(settingsGroupId: "league", week: week8)
        let routes: [CommissionerSheet] = [
            .selectionDeadline(selection8),
            .pickDeadline(pick8),
            .adminGameBrowse,
            .members,
            .selections(week8),
            .slate(week8)
        ]
        let ids = routes.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(CommissionerSheet.selectionDeadline(selection8).id == "selectionDeadline")
        #expect(CommissionerSheet.selectionDeadline(selection8).id == CommissionerSheet.selectionDeadline(selection9).id)
        #expect(CommissionerSheet.pickDeadline(pick8).id == CommissionerSheet.pickDeadline(pick8).id)
        #expect(CommissionerSheet.selections(week8).id == CommissionerSheet.selections(week9).id)
        #expect(CommissionerSheet.selections(week8).id != CommissionerSheet.slate(week8).id)

        let amy = StandingEntry(
            id: "a",
            displayName: "Amy",
            avatarColorHex: "#111111",
            weeklyWins: 1,
            weeklyLosses: 0,
            seasonWins: 1,
            seasonLosses: 0,
            rank: 1,
            isTied: true
        )
        let bo = StandingEntry(
            id: "b",
            displayName: "Bo",
            avatarColorHex: "#222222",
            weeklyWins: 1,
            weeklyLosses: 0,
            seasonWins: 1,
            seasonLosses: 0,
            rank: 1,
            isTied: true
        )
        let capture8 = selection8.capture
        let capture9 = selection9.capture
        let forward = CommissionerSheet.rankTies(TieRankDraft(entries: [amy, bo]), capture8)
        let reversed = CommissionerSheet.rankTies(TieRankDraft(entries: [bo, amy]), capture9)
        #expect(forward.id == reversed.id)
        #expect(forward.id == "rankTies.a|b")
        #expect(forward.id != CommissionerSheet.slate(week8).id)
        #expect(!ids.contains(forward.id))
    }

    private func commissionerWeek(id: String, number: Int) -> WeekSummary {
        WeekSummary(
            id: id,
            seasonYear: 2026,
            weekNumber: number,
            status: .selection,
            slateSize: 8,
            selectionMode: .member,
            selectionsPerMember: 1,
            lockedAt: nil,
            pickDeadline: nil,
            nominationCount: 0
        )
    }

    @Test func replaceRemovesTheGameBeingSwapped() {
        let ids = GameBrowseTakenIds.make(
            nominationEventIds: ["e1", "e2"],
            slateEventIds: ["e2"],
            replacingEventId: "e1"
        )
        #expect(ids == ["e2"])
        #expect(!ids.contains("e1"))
    }
}
