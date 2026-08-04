import SwiftUI

struct GroupPicksView: View {
    @Environment(AppState.self) private var appState
    /// Collapse-by-exception keeps sections default-open without seeding from async data.
    @State private var collapsedUserIds: Set<String> = []
    @State private var isRefreshingOwnPick = false
    @State private var ownPickLoadAttempted = false

    private var members: [GroupMember] {
        appState.groupService.members
    }

    private var slateGames: [SlateGame] {
        appState.pickService.slateGames
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
        .task(id: appState.groupService.currentWeek?.id) {
            await refreshAllPicks()
        }
        .onChange(of: appState.pickService.userPick) { _, newPick in
            appState.pickService.mergeOwnPickIntoAllPicks(newPick)
        }
    }

    // MARK: - Progress

    private var progressCard: some View {
        PickemsCard {
            HStack {
                Text("\(submittedUserIds.intersection(Set(members.map(\.id))).count) of \(members.count) submitted")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Spacer()
            }
        }
    }

    // MARK: - Member section

    @ViewBuilder
    private func memberSection(_ member: GroupMember) -> some View {
        let isCollapsed = collapsedUserIds.contains(member.id)
        let pick = picksByUserId[member.id]
        let submitted = isSubmitted(member.id)
        let total = slateGames.count
        let made = madeCount(for: member.id, pick: pick, submitted: submitted)
        let remaining = max(total - made, 0)

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
                        Text(member.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PickemsColors.textPrimary)
                        HStack(spacing: 8) {
                            Text("\(made)/\(total)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PickemsColors.textSecondary)
                            if remaining > 0 {
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

            if !isCollapsed {
                VStack(spacing: 8) {
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
            if let pick, canRevealPickDetails(for: member.id) {
                ForEach(slateGames) { game in
                    PickResultRow(game: game, pickedTeamId: pick.picks[game.id], showSpread: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            } else if canRevealPickDetails(for: member.id), submitted {
                // Own submitted picks must never show the "hidden until deadline" copy.
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
            ForEach(slateGames) { game in
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
        if submitted { return slateGames.count }
        return 0
    }

    /// Own pick may be present in `allPicks` before the deadline; others' are not.
    private func canRevealPickDetails(for userId: String) -> Bool {
        userId == currentUserId
    }
}
