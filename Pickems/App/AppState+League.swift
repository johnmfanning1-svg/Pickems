import Foundation

extension AppState {
    var currentUserId: String? {
        authService.currentUserId
    }

    var isCommissioner: Bool {
        guard let group = groupService.selectedGroup,
              let userId = currentUserId else { return false }
        return group.commissionerId == userId
    }

    var needsOnboarding: Bool {
        _ = authService.onboardingRevision
        _ = groupService.groups
        _ = groupService.selectedGroup
        return AuthRouting.needsOnboarding(
            userId: currentUserId,
            hasGroup: !groupService.groups.isEmpty || groupService.selectedGroup != nil,
            hasCompletedOnboarding: currentUserId.map { authService.hasCompletedOnboarding(for: $0) } ?? false
        )
    }

    /// Sync ESPN week, then attach Firestore listeners for picks/nominations.
    func syncSelectedWeek() async {
        guard let group = groupService.selectedGroup,
              let userId = currentUserId else { return }
        await groupService.syncCurrentWeekFromESPN(groupId: group.id)
        guard let week = groupService.currentWeek else { return }
        pickService.observeWeek(groupId: group.id, weekId: week.id, userId: userId)
    }

    func joinGroup(inviteCode: String, markOnboarding: Bool = true) async throws {
        guard let user = authService.currentUser else {
            let error = GroupService.GroupError.signInRequired
            AppEvents.failure(.onboardingJoinFailed, error: error, metadata: [
                "reason": "missing_profile",
            ])
            throw error
        }
        AppEvents.track(.onboardingJoinStarted, metadata: [
            "uid": AppEvents.shortUID(user.id),
            "code_length": "\(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).count)",
        ])
        do {
            try await groupService.joinGroup(
                inviteCode: inviteCode,
                userId: user.id,
                displayName: user.displayName,
                avatarColorHex: user.avatarColorHex
            )
            if markOnboarding {
                finishOnboarding(for: user.id)
            }
            groupService.loadGroups(for: user.id)
            pendingInviteCode = nil
            AppEvents.track(.onboardingJoinSucceeded, metadata: [
                "uid": AppEvents.shortUID(user.id),
                "group_id": groupService.selectedGroup?.id ?? "nil",
            ])
        } catch {
            AppEvents.failure(.onboardingJoinFailed, error: error, metadata: [
                "uid": AppEvents.shortUID(user.id),
            ])
            throw error
        }
    }

    /// Marks onboarding complete, lands on Home, and schedules the favorite-team prompt.
    func finishOnboarding(for userId: String) {
        authService.markOnboardingComplete(for: userId)
        selectedTab = .home
        CrashReport.setValue("false", forKey: "needs_onboarding")
        scheduleFavoriteTeamPrompt()
    }

    func presentFavoriteTeamPromptIfNeeded() {
        guard let userId = currentUserId else { return }
        guard !needsOnboarding else { return }
        guard authService.currentUser?.favoriteTeamId == nil else { return }
        guard !authService.hasDismissedFavoriteTeamPrompt(for: userId) else { return }
        showFavoriteTeamPicker = true
        AppEvents.track(.favoriteTeamPromptPresented, metadata: [
            "uid": AppEvents.shortUID(userId),
        ])
    }

    /// Present after any overlapping sheet (create-league wizard) has dismissed.
    func scheduleFavoriteTeamPrompt(delayNanoseconds: UInt64 = 450_000_000) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            presentFavoriteTeamPromptIfNeeded()
        }
    }

    func rankedStandings(weekly: Bool) -> [StandingEntry] {
        guard let standings = groupService.standings else { return [] }
        let tieBreaker = groupService.selectedGroup?.rules.tieBreaker ?? .commissionerOverride
        return ScoringEngine.rankedStandings(
            entries: standings.entries,
            weekly: weekly,
            tieBreaker: tieBreaker,
            allPicks: pickService.allPicks,
            games: pickService.slateGames
        )
    }
}
