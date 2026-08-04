import SwiftUI

struct GroupPicksView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    /// Collapse-by-exception keeps sections default-open without seeding from async data.
    @State private var collapsedUserIds: Set<String> = []
    @State private var isRefreshingOwnPick = false
    @State private var ownPickLoadAttempted = false
    @State private var manageMember: GroupMember?

    private var members: [GroupMember] {
        appState.groupService.members
    }

    private var commissionerId: String? {
        appState.groupService.selectedGroup?.commissionerId
    }

    /// Prefer materialized slate games; fall back to nominations so Group Picks
    /// stays aligned with what the league has selected before materialization.
    private var displayGames: [SlateGame] {
        let slate = appState.pickService.slateGames
        if !slate.isEmpty { return slate }
        return appState.pickService.nominations.map { nom in
            SlateGame(
                id: nom.espnEventId,
                espnEventId: nom.espnEventId,
                homeTeamId: nom.homeTeamId ?? "home",
                homeTeamName: nom.homeTeamName,
                homeTeamAbbreviation: nom.homeTeamAbbreviation ?? String(nom.homeTeamName.prefix(4)).uppercased(),
                homeTeamLogoURL: nom.homeTeamLogoURL,
                awayTeamId: nom.awayTeamId ?? "away",
                awayTeamName: nom.awayTeamName,
                awayTeamAbbreviation: nom.awayTeamAbbreviation ?? String(nom.awayTeamName.prefix(4)).uppercased(),
                awayTeamLogoURL: nom.awayTeamLogoURL,
                spread: abs(nom.spread),
                spreadTeamId: nom.spreadTeamId,
                kickoff: nom.kickoff,
                status: .scheduled,
                homeScore: nil,
                awayScore: nil,
                winnerTeamId: nil
            )
        }
    }

    /// Prefer `allPicks`, but always surface the signed-in member's `userPick` pre-deadline.
    private var picksByUserId: [String: UserPick] {
        var map = Dictionary(uniqueKeysWithValues: appState.pickService.allPicks.map { ($0.userId, $0) })
        if let own = appState.pickService.userPick {
            map[own.userId] = own
        }
        return map
    }

    private var submittedUserIds: Set<String> {
        Set(appState.pickService.submissions.filter(\.isLocked).map(\.userId))
    }

    /// Picks docs are readable by all members only after lock/deadline (see firestore `picksVisibleToAll`).
    private var picksVisibleToAll: Bool {
        guard let week = appState.groupService.currentWeek else { return false }
        if week.status == .locked || week.status == .scored { return true }
        return ScoringEngine.isPastDeadline(deadline: week.pickDeadline)
    }

    private var currentUserId: String? {
        appState.authService.currentUser?.id ?? appState.authService.currentUserId
    }

    private var sortedMembers: [GroupMember] {
        members.sorted { lhs, rhs in
            let leftIsComm = lhs.id == commissionerId
            let rightIsComm = rhs.id == commissionerId
            if leftIsComm != rightIsComm { return leftIsComm && !rightIsComm }
            let leftSubmitted = isSubmitted(lhs.id)
            let rightSubmitted = isSubmitted(rhs.id)
            if leftSubmitted != rightSubmitted { return leftSubmitted && !rightSubmitted }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                progressCard

                if sortedMembers.isEmpty {
                    ContentUnavailableView(
                        "No Members",
                        systemImage: "person.3",
                        description: Text("League members will appear here.")
                    )
                    .padding(.top, 24)
                } else {
                    ForEach(sortedMembers) { member in
                        memberSection(member)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Group Picks")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .task(id: "\(appState.groupService.selectedGroup?.id ?? "")-\(appState.groupService.currentWeek?.id ?? "")") {
            await appState.syncSelectedWeek()
            await refreshAllPicks()
        }
        .onChange(of: appState.pickService.userPick) { _, newPick in
            appState.pickService.mergeOwnPickIntoAllPicks(newPick)
        }
        .sheet(item: $manageMember) { member in
            if let week = appState.groupService.currentWeek,
               let groupId = appState.groupService.selectedGroup?.id {
                CommissionerManagePicksSheet(
                    member: member,
                    week: week,
                    groupId: groupId,
                    slateGames: displayGames
                )
                .pickemsEnvironment(appState)
            }
        }
    }

    // MARK: - Progress

    private var progressCard: some View {
        PickemsCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(submittedUserIds.intersection(Set(members.map(\.id))).count) of \(members.count) submitted")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PickemsColors.textPrimary)
                    Spacer()
                    Text("\(displayGames.count) games")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                if displayGames.isEmpty {
                    Text("No slate games yet — nominate or add games to sync this view.")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Member section

    @ViewBuilder
    private func memberSection(_ member: GroupMember) -> some View {
        let isCollapsed = collapsedUserIds.contains(member.id)
        let pick = picksByUserId[member.id]
        let submitted = isSubmitted(member.id)
        let total = displayGames.count
        let made = madeCount(for: member.id, pick: pick, submitted: submitted)
        let remaining = max(total - made, 0)
        let isComm = member.id == commissionerId

        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedUserIds.remove(member.id)
                    } else {
                        collapsedUserIds.insert(member.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    InitialsAvatar(
                        initials: String(member.displayName.prefix(2)).uppercased(),
                        colorHex: member.avatarColorHex,
                        size: 32
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(member.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PickemsColors.textPrimary)
                            if isComm {
                                Image(systemName: "gavel")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.accent)
                                    .accessibilityLabel("Commissioner")
                            }
                        }
                        HStack(spacing: 8) {
                            Text("\(made)/\(total)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PickemsColors.textSecondary)
                            if remaining > 0, total > 0 {
                                Text("\(remaining) left")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PickemsColors.warning)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    StatusBadge(
                        text: submitted ? "Submitted" : "In progress",
                        color: submitted ? PickemsColors.success : PickemsColors.warning
                    )

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(PickemsColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(isCollapsed ? "Show picks" : "Hide picks")
            .accessibilityAddTraits(.isButton)
            .contextMenu {
                if appState.isCommissioner {
                    Button {
                        manageMember = member
                    } label: {
                        Label("Manage Picks…", systemImage: "gavel")
                    }
                }
            }

            if !isCollapsed {
                VStack(spacing: 8) {
                    if appState.isCommissioner {
                        Button {
                            manageMember = member
                        } label: {
                            Label("Manage picks", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                    }
                    memberBody(member: member, pick: pick, submitted: submitted)
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func memberBody(member: GroupMember, pick: UserPick?, submitted: Bool) -> some View {
        if !picksVisibleToAll {
            // Pre-deadline: submissions are public; pick docs are not. Avoid permission-error UX.
            // Commissioners can always see details when managing.
            if let pick, canRevealPickDetails(for: member.id) {
                ForEach(displayGames) { game in
                    PickResultRow(game: game, pickedTeamId: pick.picks[game.id], showSpread: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            } else if canRevealPickDetails(for: member.id), submitted {
                ownPickPendingState
            } else if submitted {
                Text("Picks hidden until the deadline")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
            } else {
                emptyPicksState(title: "No picks yet", message: "\(member.displayName) hasn't submitted.")
            }
        } else if let pick, !pick.picks.isEmpty {
            ForEach(displayGames) { game in
                PickResultRow(game: game, pickedTeamId: pick.picks[game.id], showSpread: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        } else {
            emptyPicksState(title: "No picks yet", message: "\(member.displayName) hasn't submitted.")
        }
    }

    private var ownPickPendingState: some View {
        VStack(spacing: 10) {
            if isRefreshingOwnPick || !ownPickLoadAttempted {
                ProgressView()
                Text("Loading your picks…")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
            } else {
                Text("Couldn't load your picks")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text("Try again to show your submitted picks.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                Button("Retry") {
                    Task { await refreshAllPicks() }
                }
                .buttonStyle(.bordered)
                .tint(PickemsColors.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
    }

    private func emptyPicksState(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Helpers

    private func refreshAllPicks() async {
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek else { return }
        isRefreshingOwnPick = true
        defer {
            isRefreshingOwnPick = false
            ownPickLoadAttempted = true
        }
        await appState.pickService.loadAllPicks(groupId: group.id, weekId: week.id)
        appState.pickService.mergeOwnPickIntoAllPicks(appState.pickService.userPick)
    }

    private func isSubmitted(_ userId: String) -> Bool {
        if submittedUserIds.contains(userId) { return true }
        return picksByUserId[userId]?.isLocked == true
    }

    private func madeCount(for userId: String, pick: UserPick?, submitted: Bool) -> Int {
        if let pick {
            return pick.picks.keys.count
        }
        // Submissions are public pre-deadline; locked submit requires a full slate.
        if submitted { return displayGames.count }
        return 0
    }

    /// Own pick may be present in `allPicks` before the deadline; others' are not.
    /// Commissioners can reveal any member's picks for management.
    private func canRevealPickDetails(for userId: String) -> Bool {
        userId == currentUserId || appState.isCommissioner
    }
}
