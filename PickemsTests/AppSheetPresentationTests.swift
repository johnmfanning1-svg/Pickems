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
