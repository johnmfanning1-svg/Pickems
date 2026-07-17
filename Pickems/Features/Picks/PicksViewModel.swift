import SwiftUI

@MainActor
@Observable
final class PicksViewModel {
    var draftPicks: [String: String] = [:]
    var confidenceGameId: String?
    var showGameBrowse = false
    var espnGames: [ESPNGame] = []
    var isLoadingGames = false
    var livePickCards: [String: ESPNLiveGameCard] = [:]
    var showConfirmSubmit = false
    var showConfirmNominations = false
    var spreadEditGame: SlateGame?
    /// Local acknowledgement that the member finished nominating their games this week.
    var didSubmitNominations = false

    private var liveRefreshTask: Task<Void, Never>?

    func loadWeek(appState: AppState) async {
        await appState.syncSelectedWeek()
        if let picks = appState.pickService.userPick?.picks, !picks.isEmpty {
            draftPicks = picks
        }
        confidenceGameId = appState.pickService.userPick?.confidenceGameId
        refreshNominationSubmissionState(appState: appState)
    }

    // MARK: - Nomination submission (local acknowledgement)

    private func nominationsSubmittedKey(groupId: String, weekId: String, userId: String) -> String {
        "pickems.nominationsSubmitted.\(groupId).\(weekId).\(userId)"
    }

    func refreshNominationSubmissionState(appState: AppState) {
        guard let groupId = appState.groupService.selectedGroup?.id,
              let weekId = appState.groupService.currentWeek?.id,
              let userId = appState.currentUserId else {
            didSubmitNominations = false
            return
        }
        didSubmitNominations = UserDefaults.standard.bool(
            forKey: nominationsSubmittedKey(groupId: groupId, weekId: weekId, userId: userId)
        )
    }

    func submitNominations(appState: AppState) {
        guard let groupId = appState.groupService.selectedGroup?.id,
              let weekId = appState.groupService.currentWeek?.id,
              let userId = appState.currentUserId else { return }
        UserDefaults.standard.set(
            true,
            forKey: nominationsSubmittedKey(groupId: groupId, weekId: weekId, userId: userId)
        )
        didSubmitNominations = true
        PickemsHaptics.success()
    }

    private func clearNominationSubmission(appState: AppState) {
        guard let groupId = appState.groupService.selectedGroup?.id,
              let weekId = appState.groupService.currentWeek?.id,
              let userId = appState.currentUserId else { return }
        UserDefaults.standard.set(
            false,
            forKey: nominationsSubmittedKey(groupId: groupId, weekId: weekId, userId: userId)
        )
        didSubmitNominations = false
    }

    /// Re-opens a submitted pick for editing before the deadline by saving it back as a draft.
    func unlockPicksForEditing(appState: AppState) {
        saveDraft(appState: appState)
        PickemsHaptics.lightImpact()
    }

    func syncDraftFromServer(_ picks: [String: String]?, confidenceGameId: String? = nil) {
        if let picks, !picks.isEmpty {
            draftPicks = picks
        }
        if let confidenceGameId {
            self.confidenceGameId = confidenceGameId
        }
    }

    func startLiveRefresh(week: WeekSummary, appState: AppState) {
        liveRefreshTask = LiveScoreRefresh.start(existing: liveRefreshTask) { [weak self] in
            await self?.refreshLiveResults(week: week, appState: appState)
        }
    }

    func stopLiveRefresh() {
        LiveScoreRefresh.stop(&liveRefreshTask)
    }

    func loadESPNGames(appState: AppState) async {
        isLoadingGames = true
        defer { isLoadingGames = false }
        do {
            let weekInfo = try await ESPNService.shared.currentWeek()
            espnGames = try await ESPNService.shared.fetchScoreboard(week: weekInfo.weekNumber)
        } catch {
            appState.pickService.errorMessage = error.localizedDescription
        }
    }

    func handleGameSelection(_ game: ESPNGame, appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek,
              let user = appState.authService.currentUser else { return }

        Task {
            do {
                let rules = group.rules
                if rules.selectionMode == .commissioner {
                    try await appState.pickService.submitCommissionerGame(
                        groupId: group.id,
                        weekId: week.id,
                        game: game.toSlateGame(),
                        rules: rules
                    )
                } else {
                    try await appState.pickService.submitNomination(
                        groupId: group.id,
                        weekId: week.id,
                        nomination: Nomination(
                            id: "",
                            submittedBy: user.id,
                            submitterName: user.displayName,
                            espnEventId: game.espnEventId,
                            spread: game.spread ?? 0,
                            spreadTeamId: game.spreadTeamId ?? game.homeTeamId,
                            homeTeamId: game.homeTeamId,
                            homeTeamName: game.homeTeamName,
                            homeTeamAbbreviation: game.homeTeamAbbreviation,
                            homeTeamLogoURL: game.homeTeamLogoURL,
                            awayTeamId: game.awayTeamId,
                            awayTeamName: game.awayTeamName,
                            awayTeamAbbreviation: game.awayTeamAbbreviation,
                            awayTeamLogoURL: game.awayTeamLogoURL,
                            kickoff: game.kickoff,
                            createdAt: Date()
                        ),
                        rules: rules
                    )
                }
                PickemsHaptics.success()
                showGameBrowse = false
            } catch {
                appState.pickService.errorMessage = error.localizedDescription
            }
        }
    }

    func saveDraft(appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek,
              let user = appState.authService.currentUser else { return }
        Task {
            do {
                try await appState.pickService.savePickDraft(
                    groupId: group.id,
                    weekId: week.id,
                    userId: user.id,
                    displayName: user.displayName,
                    picks: draftPicks,
                    confidenceGameId: group.rules.allowConfidencePick ? confidenceGameId : nil
                )
            } catch {
                appState.pickService.errorMessage = error.localizedDescription
            }
        }
    }

    func submitPicks(week: WeekSummary, appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let user = appState.authService.currentUser else { return }
        Task {
            do {
                try await appState.pickService.submitPicks(
                    groupId: group.id,
                    weekId: week.id,
                    userId: user.id,
                    displayName: user.displayName,
                    picks: draftPicks,
                    deadline: week.pickDeadline,
                    confidenceGameId: group.rules.allowConfidencePick ? confidenceGameId : nil,
                    allowLatePicks: group.rules.allowLatePicks
                )
                PickemsHaptics.success()
            } catch {
                appState.pickService.errorMessage = error.localizedDescription
            }
        }
    }

    func lockSlateEarly(appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek else { return }
        let kickoffs = appState.pickService.nominations.map(\.kickoff)
        guard !kickoffs.isEmpty else { return }
        Task {
            do {
                try await appState.pickService.materializeNominationsIfNeeded(
                    groupId: group.id,
                    weekId: week.id
                )
                try await appState.groupService.lockSlateEarly(
                    groupId: group.id,
                    weekId: week.id,
                    rules: group.rules,
                    kickoffs: kickoffs
                )
            } catch {
                appState.groupService.errorMessage = error.localizedDescription
            }
        }
    }

    func removeNomination(_ nomination: Nomination, rules: GroupRules, appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek,
              let userId = appState.currentUserId else { return }
        Task {
            do {
                try await appState.pickService.removeNomination(
                    groupId: group.id,
                    weekId: week.id,
                    nomination: nomination,
                    rules: rules,
                    isCommissioner: appState.isCommissioner,
                    userId: userId
                )
                // Editing selections clears the "submitted" acknowledgement so the
                // member can review and re-submit their final games.
                if nomination.submittedBy == userId {
                    clearNominationSubmission(appState: appState)
                }
            } catch {
                appState.pickService.errorMessage = error.localizedDescription
            }
        }
    }

    func removeCommissionerGame(_ game: SlateGame, week: WeekSummary, appState: AppState) {
        guard let group = appState.groupService.selectedGroup else { return }
        Task {
            do {
                try await appState.pickService.removeCommissionerGame(
                    groupId: group.id,
                    weekId: week.id,
                    gameId: game.id,
                    weekStatus: week.status
                )
            } catch {
                appState.pickService.errorMessage = error.localizedDescription
            }
        }
    }

    func updateSpread(_ game: SlateGame, spread: Double, spreadTeamId: String, appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek else { return }
        Task {
            do {
                try await appState.pickService.updateGameSpread(
                    groupId: group.id,
                    weekId: week.id,
                    gameId: game.id,
                    spread: spread,
                    spreadTeamId: spreadTeamId
                )
            } catch {
                appState.pickService.errorMessage = error.localizedDescription
            }
        }
    }

    func bulkImportScheduled(week: WeekSummary, rules: GroupRules, appState: AppState) async {
        guard let group = appState.groupService.selectedGroup else { return }
        do {
            let espn = try await ESPNService.shared.fetchScoreboard(week: week.weekNumber)
            let scheduled = espn.filter { $0.status == .scheduled }.map { $0.toSlateGame() }
            try await appState.pickService.bulkImportGames(
                groupId: group.id,
                weekId: week.id,
                games: scheduled,
                rules: rules
            )
            PickemsHaptics.success()
        } catch {
            appState.pickService.errorMessage = error.localizedDescription
        }
    }

    private func refreshLiveResults(week: WeekSummary, appState: AppState) async {
        let slateIds = Set(appState.pickService.slateGames.map(\.espnEventId))
        guard !slateIds.isEmpty else { return }
        do {
            let weekInfo = try await ESPNService.shared.currentWeek()
            let cards = try await ESPNService.shared.liveGameCards(
                week: weekInfo.weekNumber,
                slateEventIds: slateIds,
                userPicks: draftPicks,
                slateGames: appState.pickService.slateGames
            )
            livePickCards = Dictionary(uniqueKeysWithValues: cards.map { ($0.espnEventId, $0) })
        } catch {
            // Live refresh is best-effort during locked weeks.
        }
    }
}
