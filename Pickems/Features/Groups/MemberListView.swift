import SwiftUI

struct MemberListView: View {
    @Environment(AppState.self) private var appState

    @State private var showLeaveConfirm = false
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
                    }
                } header: {
                    if let group = appState.groupService.selectedGroup {
                        Text("\(group.memberCount) members in \(group.name)")
                    }
                } footer: {
                    if isCommissioner {
                        Text("Remove members or transfer commissioner in Commissioner Settings.")
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
        .alert("Leave this league?", isPresented: $showLeaveConfirm) {
            Button("Leave League", role: .destructive) { performLeave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll lose access to this league until you rejoin with the invite code.")
        }
    }

    @ViewBuilder
    private var leagueActionsSection: some View {
        Section {
            if !isCommissioner {
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
                Text("League admin — remove members, transfer commissioner, or delete the league — lives in Commissioner Settings.")
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
