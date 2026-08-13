import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    var cfbWeek: CFBWeekInfo?
    var liveGames: [ESPNLiveGameCard] = []
    var slateGames: [ESPNLiveGameCard] = []
    var isLoading = false
    var errorMessage: String?
    var newsItems: [ESPNNewsItem] = []

    private var refreshTask: Task<Void, Never>?

    func startLiveUpdates(appState: AppState) {
        refreshTask = LiveScoreRefresh.start(existing: refreshTask) {
            await self.refresh(appState: appState)
        }
    }

    func stopLiveUpdates() {
        LiveScoreRefresh.stop(&refreshTask)
    }

    func refresh(appState: AppState) async {
        isLoading = liveGames.isEmpty
        errorMessage = nil

        if let groupId = appState.groupService.selectedGroup?.id,
           appState.groupService.cfbWeek == nil {
            await appState.groupService.syncCurrentWeekFromESPN(groupId: groupId)
        }

        do {
            let weekInfo = try await ESPNService.shared.currentWeek()
            cfbWeek = weekInfo

            let slateGames = appState.pickService.slateGames
            let slateIds = Set(slateGames.map(\.espnEventId))
            let userPicks = appState.pickService.userPick?.picks ?? [:]
            let weekNumber = appState.groupService.currentWeek?.weekNumber ?? weekInfo.weekNumber

            let allCards = try await ESPNService.shared.liveGameCards(
                week: weekNumber,
                seasonType: weekInfo.seasonType,
                slateEventIds: slateIds,
                userPicks: userPicks,
                slateGames: slateGames
            )

            liveGames = allCards
            self.slateGames = allCards.filter(\.isSlateGame)

            newsItems = (try? await ESPNService.shared.fetchNews(limit: 6)) ?? []
        } catch {
            errorMessage = UserFacingError.message(for: error)
            AppLog.error(AppLog.network, "home refresh failed", error: error)
        }

        isLoading = false
    }
}
