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
        guard let userId = currentUserId else { return true }
        let hasGroup = !groupService.groups.isEmpty || groupService.selectedGroup != nil
        return !hasGroup && !authService.hasCompletedOnboarding(for: userId)
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
            throw GroupService.GroupError.invalidInviteCode
        }
        try await groupService.joinGroup(
            inviteCode: inviteCode,
            userId: user.id,
            displayName: user.displayName,
            avatarColorHex: user.avatarColorHex
        )
        if markOnboarding {
            authService.markOnboardingComplete(for: user.id)
            presentFavoriteTeamPromptIfNeeded()
        }
        groupService.loadGroups(for: user.id)
        pendingInviteCode = nil
    }

    func presentFavoriteTeamPromptIfNeeded() {
        guard let userId = currentUserId else { return }
        guard !needsOnboarding else { return }
        guard authService.currentUser?.favoriteTeamId == nil else { return }
        guard !authService.hasDismissedFavoriteTeamPrompt(for: userId) else { return }
        showFavoriteTeamPicker = true
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
