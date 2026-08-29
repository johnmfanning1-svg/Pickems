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
    var teamRanks: TeamRankLookup = .empty

    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    /// User pull-to-refresh in flight. Background live ticks must not cancel or outrank it.
    private var forceRefreshCount = 0
    /// Generation of the newest forced pull; older forced fetches must not overwrite it.
    private var latestForceGeneration: Int?

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
        // Restarting the loop cancels the previous task. Don't do that while a
        // user pull is fetching — that discard leaves stale `liveGames` on screen.
        if forceRefreshCount > 0, refreshTask != nil { return }
        refreshTask = LiveScoreRefresh.start(existing: refreshTask) {
            guard self.forceRefreshCount == 0 else { return }
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

    func refresh(appState: AppState, showLoading: Bool? = nil, forceRefresh: Bool = false) async {
        if forceRefresh {
            forceRefreshCount += 1
        } else if forceRefreshCount > 0 {
            return
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        if forceRefresh {
            latestForceGeneration = generation
        }
        let hadCachedScores = !liveGames.isEmpty
        isLoading = showLoading ?? !hadCachedScores
        isRefreshingContent = hadCachedScores

        defer {
            if forceRefresh {
                forceRefreshCount = max(0, forceRefreshCount - 1)
                if latestForceGeneration == generation, forceRefreshCount == 0 {
                    latestForceGeneration = nil
                }
            }
            if generation == refreshGeneration {
                isLoading = false
                isRefreshingContent = false
            }
        }

        if forceRefresh {
            await appState.refreshLeagueData()
            guard shouldApplyRefresh(generation: generation, forceRefresh: true) else { return }
        }

        if let groupId = appState.groupService.selectedGroup?.id,
           appState.groupService.cfbWeek == nil {
            await appState.groupService.syncCurrentWeekFromESPN(groupId: groupId)
            guard shouldApplyRefresh(generation: generation, forceRefresh: forceRefresh) else { return }
        }

        do {
            let weekInfo = try await ESPNService.shared.currentWeek(forceRefresh: forceRefresh)
            guard shouldApplyRefresh(generation: generation, forceRefresh: forceRefresh) else { return }
            cfbWeek = weekInfo

            let weeks = await ESPNService.shared.seasonWeeks(year: weekInfo.seasonYear)
            if shouldApplyRefresh(generation: generation, forceRefresh: forceRefresh) {
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
                    slateGames: slateGames,
                    forceRefresh: forceRefresh
                ).matching(seasonYear: browse.seasonYear, appWeekNumber: browse.weekNumber)
            } else if let week = appState.groupService.currentWeek {
                allCards = try await ESPNService.shared.liveGameCards(
                    for: week,
                    slateEventIds: slateIds,
                    userPicks: userPicks,
                    slateGames: slateGames,
                    forceRefresh: forceRefresh
                )
            } else {
                let appWeek = CFBWeekCalendar.resolve(espn: weekInfo)
                allCards = try await ESPNService.shared.liveGameCards(
                    week: appWeek.espnWeekNumber,
                    seasonType: weekInfo.seasonType,
                    slateEventIds: slateIds,
                    userPicks: userPicks,
                    slateGames: slateGames,
                    forceRefresh: forceRefresh
                ).matching(seasonYear: seasonYear, appWeekNumber: appWeek.weekNumber)
            }

            guard shouldApplyRefresh(generation: generation, forceRefresh: forceRefresh) else { return }
            // Stale-while-revalidate: only replace when the fetch succeeded.
            liveGames = allCards
            self.slateGames = allCards.filter(\.isSlateGame)
            teamRanks = TeamRankLookup(cards: allCards)

            if let news = try? await ESPNService.shared.fetchNews(limit: 6), !news.isEmpty {
                guard shouldApplyRefresh(generation: generation, forceRefresh: forceRefresh) else { return }
                newsItems = news
            }
            errorMessage = nil
        } catch {
            if shouldApplyRefresh(generation: generation, forceRefresh: forceRefresh),
               !UserFacingError.isCancellation(error) {
                // Keep cached scores/news on screen; surface a soft error only when we have nothing.
                if !hadCachedScores {
                    errorMessage = UserFacingError.message(for: error)
                }
                AppLog.error(AppLog.network, "home refresh failed", error: error)
            }
        }
    }

    /// Forced pulls keep their results unless a newer forced pull started.
    /// Background ticks never apply while a forced pull is in flight.
    private func shouldApplyRefresh(generation: Int, forceRefresh: Bool) -> Bool {
        if forceRefresh {
            return latestForceGeneration == generation
        }
        return generation == refreshGeneration && forceRefreshCount == 0
    }
}
