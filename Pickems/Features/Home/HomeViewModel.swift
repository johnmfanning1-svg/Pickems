import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    var cfbWeek: CFBWeekInfo?
    var liveGames: [ESPNLiveGameCard] = []
    var slateGames: [ESPNLiveGameCard] = []
    var isLoading = false
    /// True while a refresh is in flight but cached rows may still be on screen.
    var isRefreshingContent = false
    var errorMessage: String?
    var newsItems: [ESPNNewsItem] = []
    /// Season week strip for the CFB This Week picker (Pickems week numbers).
    var seasonWeeks: [CFBSeasonWeek] = []
    /// User-selected browse week for the scoreboard; nil means follow current ESPN/league week.
    var selectedBrowseWeek: CFBSeasonWeek?

    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    var scoreboardWeekLabel: String {
        if let selectedBrowseWeek {
            return "Week \(selectedBrowseWeek.weekNumber)"
        }
        if let cfbWeek {
            let app = CFBWeekCalendar.resolve(espn: cfbWeek)
            return "Week \(app.weekNumber)"
        }
        return "This Week"
    }

    func startLiveUpdates(appState: AppState) {
        refreshTask = LiveScoreRefresh.start(existing: refreshTask) {
            await self.refresh(appState: appState)
        }
    }

    func stopLiveUpdates() {
        LiveScoreRefresh.stop(&refreshTask)
    }

    func selectBrowseWeek(_ week: CFBSeasonWeek?, appState: AppState) {
        selectedBrowseWeek = week
        Task { await refresh(appState: appState, showLoading: false) }
    }

    func refresh(appState: AppState, showLoading: Bool? = nil) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let hadCachedScores = !liveGames.isEmpty
        isLoading = showLoading ?? !hadCachedScores
        isRefreshingContent = hadCachedScores

        if let groupId = appState.groupService.selectedGroup?.id,
           appState.groupService.cfbWeek == nil {
            await appState.groupService.syncCurrentWeekFromESPN(groupId: groupId)
            guard generation == refreshGeneration else { return }
        }

        do {
            let weekInfo = try await ESPNService.shared.currentWeek()
            guard generation == refreshGeneration else { return }
            cfbWeek = weekInfo

            let weeks = await ESPNService.shared.seasonWeeks(year: weekInfo.seasonYear)
            if generation == refreshGeneration {
                seasonWeeks = weeks
                if let selected = selectedBrowseWeek,
                   !weeks.contains(where: { $0.id == selected.id }) {
                    selectedBrowseWeek = nil
                }
            }

            let slateGames = appState.pickService.slateGames
            let slateIds = Set(slateGames.map(\.espnEventId))
            let userPicks = appState.pickService.userPick?.picks ?? [:]
            let seasonYear = appState.groupService.currentWeek?.seasonYear ?? weekInfo.seasonYear

            let allCards: [ESPNLiveGameCard]
            if let browse = selectedBrowseWeek {
                allCards = try await ESPNService.shared.liveGameCards(
                    week: browse.espnWeekNumber,
                    seasonType: weekInfo.seasonType,
                    slateEventIds: slateIds,
                    userPicks: userPicks,
                    slateGames: slateGames
                ).matching(seasonYear: browse.seasonYear, appWeekNumber: browse.weekNumber)
            } else if let week = appState.groupService.currentWeek {
                allCards = try await ESPNService.shared.liveGameCards(
                    for: week,
                    slateEventIds: slateIds,
                    userPicks: userPicks,
                    slateGames: slateGames
                )
            } else {
                let appWeek = CFBWeekCalendar.resolve(espn: weekInfo)
                allCards = try await ESPNService.shared.liveGameCards(
                    week: appWeek.espnWeekNumber,
                    seasonType: weekInfo.seasonType,
                    slateEventIds: slateIds,
                    userPicks: userPicks,
                    slateGames: slateGames
                ).matching(seasonYear: seasonYear, appWeekNumber: appWeek.weekNumber)
            }

            guard generation == refreshGeneration else { return }
            // Stale-while-revalidate: only replace when the fetch succeeded.
            liveGames = allCards
            self.slateGames = allCards.filter(\.isSlateGame)

            if let news = try? await ESPNService.shared.fetchNews(limit: 6), !news.isEmpty {
                guard generation == refreshGeneration else { return }
                newsItems = news
            }
            errorMessage = nil
        } catch {
            if generation == refreshGeneration, !UserFacingError.isCancellation(error) {
                // Keep cached scores/news on screen; surface a soft error only when we have nothing.
                if !hadCachedScores {
                    errorMessage = UserFacingError.message(for: error)
                }
                AppLog.error(AppLog.network, "home refresh failed", error: error)
            }
        }

        if generation == refreshGeneration {
            isLoading = false
            isRefreshingContent = false
        }
    }
}
