import SwiftUI

struct MemberListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    @State private var memberToRemove: GroupMember?
    @State private var memberToPromote: GroupMember?
    @State private var showLeaveConfirm = false
    @State private var showDeleteConfirm = false
    @State private var actionError: String?
    @State private var isWorking = false

    private var sortedMembers: [GroupMember] {
        appState.groupService.members.sorted {
            let leftIsComm = $0.id == commissionerId
            let rightIsComm = $1.id == commissionerId
            if leftIsComm != rightIsComm { return leftIsComm && !rightIsComm }
            if $0.seasonWins != $1.seasonWins { return $0.seasonWins > $1.seasonWins }
            return $0.battingAverage > $1.battingAverage
        }
    }

    private var commissionerId: String? {
        appState.groupService.selectedGroup?.commissionerId
    }

    private var currentUserId: String? {
        appState.authService.currentUser?.id
    }

    private var isCommissioner: Bool { appState.isCommissioner }

    private var otherMembers: [GroupMember] {
        sortedMembers.filter { $0.id != commissionerId }
    }

    var body: some View {
        List {
            if sortedMembers.isEmpty {
                ContentUnavailableView(
                    "No Members",
                    systemImage: "person.3",
                    description: Text("Members appear here once they join the group.")
                )
            } else {
                Section {
                    ForEach(sortedMembers) { member in
                        MemberRow(
                            member: member,
                            isCommissioner: member.id == commissionerId,
                            career: appState.groupService.careerRecord(for: member.id)
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isCommissioner, member.id != commissionerId {
                                Button("Remove", role: .destructive) {
                                    memberToRemove = member
                                }
                                Button("Make Commissioner") {
                                    memberToPromote = member
                                }
                                .tint(theme.accent)
                            }
                        }
                        .contextMenu {
                            if isCommissioner, member.id != commissionerId {
                                Button {
                                    memberToPromote = member
                                } label: {
                                    Label("Make Commissioner", systemImage: "gavel")
                                }
                                Button(role: .destructive) {
                                    memberToRemove = member
                                } label: {
                                    Label("Remove from League", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    }
                } header: {
                    if let group = appState.groupService.selectedGroup {
                        Text("\(group.memberCount) members in \(group.name)")
                    }
                } footer: {
                    if isCommissioner {
                        Text("Swipe a member to remove them or transfer commissioner. Only one commissioner at a time.")
                    }
                }

                leagueActionsSection
            }

            if let actionError {
                Section {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(PickemsColors.warning)
                        .listRowBackground(PickemsColors.cardBackground)
                }
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(PickemsColors.background)
        .disabled(isWorking)
        .alert(
            "Remove \(memberToRemove?.displayName ?? "member")?",
            isPresented: Binding(
                get: { memberToRemove != nil },
                set: { if !$0 { memberToRemove = nil } }
            )
        ) {
            Button("Remove Member", role: .destructive) {
                if let member = memberToRemove { performRemove(member) }
                memberToRemove = nil
            }
            Button("Cancel", role: .cancel) { memberToRemove = nil }
        } message: {
            Text("They lose access to this league’s picks and standings. They can rejoin later with the invite code.")
        }
        .alert(
            "Make \(memberToPromote?.displayName ?? "member") the commissioner?",
            isPresented: Binding(
                get: { memberToPromote != nil },
                set: { if !$0 { memberToPromote = nil } }
            )
        ) {
            Button("Transfer Commissioner", role: .destructive) {
                if let member = memberToPromote { performTransfer(to: member) }
                memberToPromote = nil
            }
            Button("Cancel", role: .cancel) { memberToPromote = nil }
        } message: {
            Text("You will become a regular member. Only one commissioner is allowed at a time.")
        }
        .alert("Leave this league?", isPresented: $showLeaveConfirm) {
            Button("Leave League", role: .destructive) { performLeave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll lose access to this league until you rejoin with the invite code.")
        }
        .alert("Delete this league permanently?", isPresented: $showDeleteConfirm) {
            Button("Delete League", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the league, invite code, members, picks, standings, and season history. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var leagueActionsSection: some View {
        Section {
            if isCommissioner {
                if !otherMembers.isEmpty {
                    Menu {
                        ForEach(otherMembers) { member in
                            Button(member.displayName) {
                                memberToPromote = member
                            }
                        }
                    } label: {
                        Label("Transfer Commissioner…", systemImage: "gavel")
                            .foregroundStyle(theme.accent)
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                    .accessibilityHint("Choose one member to become the only commissioner")
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete League", systemImage: "trash")
                }
                .listRowBackground(PickemsColors.cardBackground)
                .accessibilityHint("Permanently delete this league and all of its data")
            } else {
                Button(role: .destructive) {
                    showLeaveConfirm = true
                } label: {
                    Label("Leave League", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("League")
        } footer: {
            if isCommissioner {
                Text("Transfer commissioner before leaving if others remain. Deleting wipes all league data for everyone.")
            }
        }
    }

    private func performRemove(_ member: GroupMember) {
        guard let groupId = appState.groupService.selectedGroup?.id else { return }
        isWorking = true
        actionError = nil
        Task {
            defer { isWorking = false }
            do {
                try await appState.groupService.removeMember(groupId: groupId, userId: member.id)
                PickemsHaptics.success()
            } catch {
                actionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func performTransfer(to member: GroupMember) {
        guard let groupId = appState.groupService.selectedGroup?.id else { return }
        isWorking = true
        actionError = nil
        Task {
            defer { isWorking = false }
            do {
                try await appState.groupService.transferCommissioner(groupId: groupId, toUserId: member.id)
                PickemsHaptics.success()
            } catch {
                actionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func performLeave() {
        guard let groupId = appState.groupService.selectedGroup?.id,
              let userId = currentUserId else { return }
        isWorking = true
        actionError = nil
        Task {
            defer { isWorking = false }
            do {
                try await appState.groupService.leaveGroup(groupId: groupId, userId: userId)
                PickemsHaptics.success()
            } catch {
                actionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func performDelete() {
        guard let groupId = appState.groupService.selectedGroup?.id else { return }
        isWorking = true
        actionError = nil
        Task {
            defer { isWorking = false }
            do {
                try await appState.groupService.deleteGroup(groupId: groupId)
                PickemsHaptics.success()
            } catch {
                actionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }
}

struct MemberRow: View {
    @Environment(\.themePalette) private var theme
    let member: GroupMember
    let isCommissioner: Bool
    var career: CareerRecord? = nil

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(
                initials: member.initials,
                colorHex: member.avatarColorHex,
                imageURL: member.avatarImageURL,
                size: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.headline)
                        .foregroundStyle(PickemsColors.textPrimary)
                    if isCommissioner {
                        Image(systemName: "gavel")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.accent)
                            .accessibilityLabel("Commissioner")
                        Text("Commissioner")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.accent.opacity(0.25))
                            .foregroundStyle(theme.accent)
                            .clipShape(Capsule())
                    }
                    if let titles = career?.titles, titles > 0 {
                        Label("\(titles)", systemImage: "crown.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.accent)
                    }
                }
                Text("Joined \(member.joinedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                if let career {
                    Text("Career \(career.recordLabel) · \(career.seasonsPlayed) seasons")
                        .font(.caption2)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(member.seasonWins)-\(member.seasonLosses)")
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(String(format: "%.3f", member.battingAverage))
                    .font(.caption2)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(PickemsColors.cardBackground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let role = isCommissioner ? ", commissioner" : ""
        var label = "\(member.displayName)\(role). Season record \(member.seasonWins) wins, \(member.seasonLosses) losses. Batting average \(String(format: "%.3f", member.battingAverage))"
        if let career {
            label += ". Career \(career.recordLabel), \(career.titles) titles"
        }
        return label
    }
}
