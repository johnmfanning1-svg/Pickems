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
    var selectionBrowseIntent: SelectionBrowseIntent = .own

    enum SelectionBrowseIntent: Equatable {
        case own
        case addFor(memberId: String, displayName: String)
        case replace(Nomination)
    }

    private var liveRefreshTask: Task<Void, Never>?
    private var saveDraftTask: Task<Void, Never>?
    /// Local Pickems waiting for a Firestore echo. Stale listener snapshots must not clobber this.
    private var pendingWritePicks: [String: String]?
    /// True while `savePickDraft` / submit is on the network. Tab resync must not wipe that.
    private var writeInFlight = false

    func resetForSession() {
        draftPicks = [:]
        confidenceGameId = nil
        resetPendingWrite()
        stopLiveRefresh()
        showGameBrowse = false
        showConfirmSubmit = false
        showConfirmNominations = false
        spreadEditGame = nil
        selectionBrowseIntent = .own
        espnGames = []
        livePickCards = [:]
    }

    func loadWeek(appState: AppState) async {
        await appState.syncSelectedWeek()
        // Always mirror server — including empty clears from Group Picks / commissioner wipe.
        resetPendingWrite()
        applyServerPicks(appState.pickService.userPick?.picks, confidenceGameId: appState.pickService.userPick?.confidenceGameId)
        refreshNominationSubmissionState(appState: appState)
    }

    // MARK: - Nomination submission (shared on PickService)

    func refreshNominationSubmissionState(appState: AppState) {
        appState.pickService.refreshNominationSubmissionState(
            groupId: appState.groupService.selectedGroup?.id,
            weekId: appState.groupService.currentWeek?.id,
            userId: appState.currentUserId
        )
    }

    func submitNominations(appState: AppState) {
        guard let groupId = appState.groupService.selectedGroup?.id,
              let weekId = appState.groupService.currentWeek?.id,
              let userId = appState.currentUserId else { return }
        appState.pickService.markNominationsSubmitted(groupId: groupId, weekId: weekId, userId: userId)
        PickemsHaptics.success()
    }

    /// Re-opens submitted Selections so a member can remove a game and pick another
    /// before the Selection deadline — same idea as Edit Pickems.
    func unlockSelectionsForEditing(appState: AppState) {
        guard let groupId = appState.groupService.selectedGroup?.id,
              let week = appState.groupService.currentWeek,
              let userId = appState.currentUserId,
              WeekTransition.canRemakeSelections(week) else { return }
        appState.pickService.clearNominationsSubmitted(groupId: groupId, weekId: week.id, userId: userId)
        PickemsHaptics.lightImpact()
    }

    /// Re-opens a submitted pick for editing before the deadline by saving it back as a draft.
    func unlockPicksForEditing(appState: AppState) {
        saveDraft(appState: appState)
        PickemsHaptics.lightImpact()
    }

    /// Mirrors Firestore picks into the local draft. Empty/nil clears stale Pickems so
    /// Group Picks clears and Picks-tab UI stay in sync. Blank team ids are dropped so
    /// tap-to-clear can be re-picked. In-flight local writes win until their echo arrives
    /// so a stale empty snapshot cannot wipe a re-pick. `force` is for local writes that
    /// already landed (commissioner clear, save) — those must beat a pending draft.
    func syncDraftFromServer(
        _ picks: [String: String]?,
        confidenceGameId: String? = nil,
        force: Bool = false
    ) {
        let cleaned = PickService.sanitizedPicks(picks ?? [:])
        if force {
            resetPendingWrite()
            applyServerPicks(cleaned, confidenceGameId: confidenceGameId)
            return
        }
        if let pending = pendingWritePicks {
            if cleaned == pending {
                pendingWritePicks = nil
                applyServerPicks(cleaned, confidenceGameId: confidenceGameId)
            }
            return
        }
        applyServerPicks(cleaned, confidenceGameId: confidenceGameId)
    }

    /// Opening the Picks tab: server `userPick` wins unless a save is on the wire.
    func resyncWhenVisible(appState: AppState) {
        resyncDraftIfIdle(
            from: appState.pickService.userPick?.picks,
            confidenceGameId: appState.pickService.userPick?.confidenceGameId
        )
        refreshNominationSubmissionState(appState: appState)
    }

    func resyncDraftIfIdle(from picks: [String: String]?, confidenceGameId: String? = nil) {
        if writeInFlight { return }
        pendingWritePicks = nil
        applyServerPicks(picks, confidenceGameId: confidenceGameId)
    }

    /// Test seam: mark a local write that must not be overwritten by a stale snapshot.
    func markPendingWrite(_ picks: [String: String], inFlight: Bool = false) {
        pendingWritePicks = PickService.sanitizedPicks(picks)
        writeInFlight = inFlight
    }

    func resetPendingWrite() {
        pendingWritePicks = nil
        writeInFlight = false
        saveDraftTask?.cancel()
        saveDraftTask = nil
    }

    private func applyServerPicks(_ picks: [String: String]?, confidenceGameId: String?) {
        let cleaned = PickService.sanitizedPicks(picks ?? [:])
        draftPicks = cleaned
        if let confidenceGameId, cleaned.keys.contains(confidenceGameId) {
            self.confidenceGameId = confidenceGameId
        } else {
            self.confidenceGameId = nil
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
            if let week = appState.groupService.currentWeek {
                espnGames = try await ESPNService.shared.fetchScoreboard(for: week)
            } else {
                let weekInfo = try await ESPNService.shared.currentWeek()
                let app = CFBWeekCalendar.resolve(espn: weekInfo)
                espnGames = try await ESPNService.shared.fetchScoreboard(
                    week: app.espnWeekNumber,
                    seasonType: weekInfo.seasonType
                ).matching(seasonYear: app.seasonYear, appWeekNumber: app.weekNumber)
            }
        } catch {
            espnGames = []
            UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
        }
    }

    func browseGames(appState: AppState, present: Bool = true) async {
        await loadESPNGames(appState: appState)
        if espnGames.isEmpty, appState.pickService.errorMessage != nil {
            return
        }
        if present { showGameBrowse = true }
    }

    func beginAddSelection(for member: GroupMember, appState: AppState) {
        selectionBrowseIntent = .addFor(memberId: member.id, displayName: member.displayName)
        Task { await browseGames(appState: appState) }
    }

    func beginReplaceSelection(_ nomination: Nomination, appState: AppState) {
        selectionBrowseIntent = .replace(nomination)
        Task { await browseGames(appState: appState) }
    }

    func handleGameSelection(_ game: ESPNGame, appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek,
              let user = appState.authService.currentUser else { return }

        let intent = selectionBrowseIntent
        Task {
            do {
                let rules = group.rules
                try await applyGameSelection(
                    game,
                    intent: intent,
                    group: group,
                    week: week,
                    user: user,
                    rules: rules,
                    appState: appState
                )
                PickemsHaptics.success()
                selectionBrowseIntent = .own
                showGameBrowse = false
            } catch {
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
            }
        }
    }

    private func applyGameSelection(
        _ game: ESPNGame,
        intent: SelectionBrowseIntent,
        group: PickemGroup,
        week: WeekSummary,
        user: UserProfile,
        rules: GroupRules,
        appState: AppState
    ) async throws {
        switch intent {
        case .replace(let nomination):
            try await appState.pickService.replaceNomination(
                groupId: group.id,
                weekId: week.id,
                nomination: nomination,
                game: game,
                rules: rules,
                week: week,
                isCommissioner: appState.isCommissioner,
                userId: user.id
            )
        case .addFor(let memberId, let displayName):
            try await appState.pickService.submitNomination(
                groupId: group.id,
                weekId: week.id,
                nomination: Nomination.fromESPNGame(
                    game,
                    submittedBy: memberId,
                    submitterName: displayName
                ),
                rules: rules,
                week: week,
                memberIds: group.memberIds,
                isCommissioner: true
            )
        case .own:
            let selectionMode = week.selectionMode
            let commissionerFill =
                appState.isCommissioner
                && (
                    (selectionMode == .member && week.isSelectionDeadlinePassed)
                    || week.status == .picking
                )

            if selectionMode == .commissioner || commissionerFill {
                try await appState.pickService.submitCommissionerGame(
                    groupId: group.id,
                    weekId: week.id,
                    game: game.toSlateGame(),
                    rules: rules,
                    week: week
                )
            } else {
                try await appState.pickService.submitNomination(
                    groupId: group.id,
                    weekId: week.id,
                    nomination: Nomination.fromESPNGame(
                        game,
                        submittedBy: user.id,
                        submitterName: user.displayName
                    ),
                    rules: rules,
                    week: week,
                    memberIds: group.memberIds,
                    isCommissioner: appState.isCommissioner
                )
            }
        }
    }

    func saveDraft(appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek,
              let user = appState.authService.currentUser else { return }
        let gameIds = Set(appState.pickService.slateGames.map(\.id))
        var picks = PickService.sanitizedPicks(draftPicks)
        if !gameIds.isEmpty {
            picks = picks.filter { gameIds.contains($0.key) }
        }
        if picks != draftPicks {
            draftPicks = picks
        }
        if let cid = confidenceGameId, !picks.keys.contains(cid) {
            confidenceGameId = nil
        }
        let confidenceToSave = group.rules.allowConfidencePick ? confidenceGameId : nil
        pendingWritePicks = picks
        writeInFlight = true
        let previous = saveDraftTask
        saveDraftTask = Task {
            _ = await previous?.value
            guard !Task.isCancelled else {
                if pendingWritePicks == picks { writeInFlight = false }
                return
            }
            do {
                try await appState.pickService.savePickDraft(
                    groupId: group.id,
                    weekId: week.id,
                    userId: user.id,
                    displayName: user.displayName,
                    picks: picks,
                    confidenceGameId: confidenceToSave,
                    week: week,
                    allowLatePicks: group.rules.allowLatePicks
                )
                if pendingWritePicks == picks {
                    writeInFlight = false
                }
            } catch {
                if pendingWritePicks == picks {
                    pendingWritePicks = nil
                    writeInFlight = false
                }
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
            }
        }
    }

    func submitPicks(week: WeekSummary, appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let user = appState.authService.currentUser else { return }
        let picks = PickService.sanitizedPicks(draftPicks)
        let confidence = group.rules.allowConfidencePick ? confidenceGameId : nil
        pendingWritePicks = picks
        writeInFlight = true
        Task {
            _ = await saveDraftTask?.value
            guard !Task.isCancelled else {
                if pendingWritePicks == picks { writeInFlight = false }
                return
            }
            do {
                try await appState.pickService.submitPicks(
                    groupId: group.id,
                    weekId: week.id,
                    userId: user.id,
                    displayName: user.displayName,
                    picks: picks,
                    deadline: week.pickDeadline,
                    confidenceGameId: confidence,
                    allowLatePicks: group.rules.allowLatePicks
                )
                if pendingWritePicks == picks {
                    writeInFlight = false
                }
                PickemsHaptics.success()
            } catch {
                if pendingWritePicks == picks {
                    pendingWritePicks = nil
                    writeInFlight = false
                }
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
            }
        }
    }

    func lockSlateEarly(appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek else { return }
        Task {
            do {
                try await appState.pickService.openWeekWithCurrentSlate(
                    groupId: group.id,
                    weekId: week.id,
                    rules: group.rules
                )
            } catch {
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
            }
        }
    }

    func openWeekWithCurrentSlate(appState: AppState) {
        lockSlateEarly(appState: appState)
    }

    func reopenSelections(appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek,
              WeekTransition.canReopenSelections(week) else { return }
        Task {
            do {
                try await appState.groupService.reopenWeekForSelections(
                    groupId: group.id,
                    weekId: week.id
                )
                try await appState.pickService.clearSlateGamesForSelectionReopen(
                    groupId: group.id,
                    weekId: week.id,
                    commissionerUserId: appState.currentUserId ?? group.commissionerId,
                    commissionerName: appState.authService.currentUser?.displayName ?? "Commissioner"
                )
                PickemsHaptics.success()
            } catch {
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
            }
        }
    }

    func setSelectionDeadline(_ deadline: Date, appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek,
              let userId = appState.currentUserId else { return }
        Task {
            do {
                try await appState.groupService.setSelectionDeadline(
                    groupId: group.id,
                    weekId: week.id,
                    deadline: deadline,
                    setByUserId: userId
                )
                PickemsHaptics.success()
            } catch {
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
            }
        }
    }

    /// Commissioner sets/extends pick deadline; optionally reopens a locked week and unlocks submissions.
    func setPickDeadline(
        _ deadline: Date,
        reopenWeek: Bool,
        unlockMemberPicks: Bool,
        appState: AppState
    ) {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek else { return }
        Task {
            do {
                if reopenWeek {
                    try await appState.groupService.reopenWeekForPicking(
                        groupId: group.id,
                        weekId: week.id,
                        deadline: deadline
                    )
                } else {
                    try await appState.groupService.setPickDeadline(
                        groupId: group.id,
                        weekId: week.id,
                        deadline: deadline
                    )
                }
                if unlockMemberPicks {
                    try await appState.pickService.commissionerUnlockAllPicks(
                        groupId: group.id,
                        weekId: week.id
                    )
                }
                PickemsHaptics.success()
            } catch {
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
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
                    week: week,
                    isCommissioner: appState.isCommissioner,
                    userId: userId
                )
                let eventId = nomination.espnEventId
                for game in appState.pickService.slateGames where game.espnEventId == eventId || game.id == eventId {
                    draftPicks.removeValue(forKey: game.id)
                    if confidenceGameId == game.id { confidenceGameId = nil }
                }
                draftPicks.removeValue(forKey: eventId)
            } catch {
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
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
                    week: week
                )
                draftPicks.removeValue(forKey: game.id)
                if confidenceGameId == game.id {
                    confidenceGameId = nil
                }
            } catch {
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
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
                    game: game,
                    spread: spread,
                    spreadTeamId: spreadTeamId
                )
            } catch {
                UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
            }
        }
    }

    func bulkImportScheduled(week: WeekSummary, rules: GroupRules, appState: AppState) async {
        guard let group = appState.groupService.selectedGroup else { return }
        do {
            let espn = try await ESPNService.shared.fetchScoreboard(for: week)
            let scheduled = espn.filter { $0.status == .scheduled }.map { $0.toSlateGame() }
            try await appState.pickService.bulkImportGames(
                groupId: group.id,
                weekId: week.id,
                games: scheduled,
                rules: rules,
                week: week
            )
            PickemsHaptics.success()
        } catch {
            UserFacingError.apply(error, to: &appState.pickService.errorMessage, context: .write)
        }
    }

    private func refreshLiveResults(week: WeekSummary, appState: AppState) async {
        let slateIds = Set(appState.pickService.slateGames.map(\.espnEventId))
        guard !slateIds.isEmpty else { return }
        do {
            let cards = try await ESPNService.shared.liveGameCards(
                for: week,
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

/// Keeps the shared Picks draft in sync with `PickService.userPick` from any screen.
private struct PicksDraftSyncModifier: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.pickService.userPick) { _, newPick in
                appState.picksViewModel.syncDraftFromServer(
                    newPick?.picks,
                    confidenceGameId: newPick?.confidenceGameId
                )
            }
            .onChange(of: appState.pickService.userPickEpoch) { _, _ in
                appState.picksViewModel.syncDraftFromServer(
                    appState.pickService.userPick?.picks,
                    confidenceGameId: appState.pickService.userPick?.confidenceGameId,
                    force: true
                )
            }
            .onChange(of: appState.pickService.nominations) { _, _ in
                appState.picksViewModel.refreshNominationSubmissionState(appState: appState)
            }
    }
}

extension View {
    func syncPicksDraftFromServer() -> some View {
        modifier(PicksDraftSyncModifier())
    }
}
