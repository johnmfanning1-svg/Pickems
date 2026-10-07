import SwiftUI

/// Was the inline "Members & Ownership" section of Commissioner Settings.
/// Remove member, transfer commissioner and delete league, with their confirms.
struct CommissionerMembersSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    let groupId: String
    let commissionerId: String
    /// Called after a transfer or delete, when Commissioner Settings no longer applies.
    let onLeftCommissionerRole: () -> Void

    @State private var memberToRemove: GroupMember?
    @State private var memberToPromote: GroupMember?
    @State private var showDeleteLeagueConfirm = false
    @State private var isWorking = false
    @State private var actionError: String?

    private var otherMembers: [GroupMember] {
        appState.groupService.members
            .filter { $0.id != commissionerId }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            membersForm
        }
        .presentationDragIndicator(.visible)
    }

    private var membersForm: some View {
        Form {
            membersSection
            ownershipSection
        }
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
        .alert(removeTitle, isPresented: removePresented) {
            Button("Remove Member", role: .destructive) {
                if let member = memberToRemove { removeMember(member) }
                memberToRemove = nil
            }
            Button("Cancel", role: .cancel) { memberToRemove = nil }
        } message: {
            Text("They lose access to this league’s picks and standings. They can rejoin with the invite code.")
        }
        .alert(promoteTitle, isPresented: promotePresented) {
            Button("Transfer Commissioner", role: .destructive) {
                if let member = memberToPromote { transferCommissioner(to: member) }
                memberToPromote = nil
            }
            Button("Cancel", role: .cancel) { memberToPromote = nil }
        } message: {
            Text("You become a regular member. Only one commissioner is allowed at a time.")
        }
        .alert("Delete this league permanently?", isPresented: $showDeleteLeagueConfirm) {
            Button("Delete League", role: .destructive) { deleteLeague() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the league, invite code, members, picks, standings, and season history for everyone. This cannot be undone.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var membersSection: some View {
        Section {
            if otherMembers.isEmpty {
                Text("No other members yet. Share your invite code to grow the league.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            } else {
                ForEach(otherMembers) { (member: GroupMember) in
                    memberRow(member)
                }
            }
        } header: {
            Text("\(appState.groupService.members.count) in the league")
        } footer: {
            Text("Remove members or make one the commissioner. Only one commissioner at a time.")
        }
    }

    private var ownershipSection: some View {
        Section {
            if !otherMembers.isEmpty {
                transferMenu
            }
            Button(role: .destructive) {
                showDeleteLeagueConfirm = true
            } label: {
                Label("Delete League", systemImage: "trash")
            }
            .listRowBackground(PickemsColors.cardBackground)
            .disabled(isWorking)

            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.warning)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("Ownership")
        } footer: {
            Text("Deleting erases all picks and standings for everyone.")
        }
    }

    private var transferMenu: some View {
        Menu {
            ForEach(otherMembers) { (member: GroupMember) in
                Button(member.displayName) { memberToPromote = member }
            }
        } label: {
            Label("Transfer Commissioner…", systemImage: "gavel")
                .foregroundStyle(theme.accent)
        }
        .listRowBackground(PickemsColors.cardBackground)
        .disabled(isWorking)
    }

    private func memberRow(_ member: GroupMember) -> some View {
        HStack(spacing: 12) {
            InitialsAvatar(
                initials: member.initials,
                colorHex: member.avatarColorHex,
                imageURL: member.avatarImageURL,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .foregroundStyle(PickemsColors.textPrimary)
                Text("\(member.seasonWins)-\(member.seasonLosses) this season")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
            Spacer()
            Button {
                memberToPromote = member
            } label: {
                Image(systemName: "gavel")
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Make \(member.displayName) commissioner")
            .disabled(isWorking)

            Button(role: .destructive) {
                memberToRemove = member
            } label: {
                Image(systemName: "person.badge.minus")
                    .foregroundStyle(PickemsColors.warning)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(member.displayName)")
            .disabled(isWorking)
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    // MARK: - Alerts

    private var removePresented: Binding<Bool> {
        Binding<Bool>(
            get: { memberToRemove != nil },
            set: { (isPresented: Bool) in if !isPresented { memberToRemove = nil } }
        )
    }

    private var promotePresented: Binding<Bool> {
        Binding<Bool>(
            get: { memberToPromote != nil },
            set: { (isPresented: Bool) in if !isPresented { memberToPromote = nil } }
        )
    }

    private var removeTitle: String {
        "Remove \(memberToRemove?.displayName ?? "member")?"
    }

    private var promoteTitle: String {
        "Make \(memberToPromote?.displayName ?? "member") the commissioner?"
    }

    // MARK: - Actions

    private func removeMember(_ member: GroupMember) {
        run { try await appState.groupService.removeMember(groupId: groupId, userId: member.id) }
    }

    private func transferCommissioner(to member: GroupMember) {
        run(leavesCommissionerRole: true) {
            try await appState.groupService.transferCommissioner(groupId: groupId, toUserId: member.id)
        }
    }

    private func deleteLeague() {
        run(leavesCommissionerRole: true) {
            try await appState.groupService.deleteGroup(groupId: groupId)
        }
    }

    private func run(leavesCommissionerRole: Bool = false, _ work: @escaping () async throws -> Void) {
        actionError = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await work()
                PickemsHaptics.success()
                if leavesCommissionerRole {
                    onLeftCommissionerRole()
                }
            } catch {
                actionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }
}
