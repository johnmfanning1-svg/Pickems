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
        let routes: [CommissionerSheet] = [
            .selectionDeadline,
            .pickDeadline,
            .adminGameBrowse,
            .members,
            .selections,
            .slate
        ]
        let ids = routes.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(CommissionerSheet.selectionDeadline.id == "selectionDeadline")
        #expect(CommissionerSheet.pickDeadline.id == CommissionerSheet.pickDeadline.id)
        #expect(CommissionerSheet.selections.id != CommissionerSheet.slate.id)

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
        let forward = CommissionerSheet.rankTies(TieRankDraft(entries: [amy, bo]))
        let reversed = CommissionerSheet.rankTies(TieRankDraft(entries: [bo, amy]))
        #expect(forward.id == reversed.id)
        #expect(forward.id == "rankTies.a|b")
        #expect(forward.id != CommissionerSheet.slate.id)
        #expect(!ids.contains(forward.id))
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
