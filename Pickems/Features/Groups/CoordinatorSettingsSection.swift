import SwiftUI

/// Commissioner-only OC / DC seats. Appointment writes the group doc immediately.
struct CoordinatorSettingsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    let group: PickemGroup
    var errorMessage: String?
    let onPick: (LeagueCoordinatorRole) -> Void

    @State private var isWorking = false
    @State private var localError: String?

    private var members: [GroupMember] {
        guard appState.groupService.membersGroupId == group.id else { return [] }
        return appState.groupService.members
    }

    var body: some View {
        Section {
            seatRow(.oc)
            seatRow(.dc)
            if let shownError {
                Text(shownError)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.warning)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("Coordinators")
        } footer: {
            Text("One Offensive Coordinator and one Defensive Coordinator. They can run the week if you can't — deadlines, slate, Pickems, ties — and they can't change the league, scoring, or who the commissioner is.")
        }
    }

    private var shownError: String? { localError ?? errorMessage }

    private func seatRow(_ role: LeagueCoordinatorRole) -> some View {
        let holderId = LeagueRolePolicy.activeCoordinators(in: group).holder(of: role)
        let holderName = holderId.flatMap { id in
            members.first { $0.id == id }?.displayName
        }
        return HStack(spacing: 12) {
            Label(role.title, systemImage: role.systemImage)
                .foregroundStyle(PickemsColors.textPrimary)
            Spacer(minLength: 8)
            if let holderName {
                Text(holderName)
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .lineLimit(1)
                removeButton(role: role, name: holderName)
            } else {
                Text("None")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
            Button(holderName == nil ? "Appoint" : "Change") {
                onPick(role)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
            .foregroundStyle(theme.accent)
            .disabled(isWorking)
        }
        .listRowBackground(PickemsColors.cardBackground)
    }

    private func removeButton(role: LeagueCoordinatorRole, name: String) -> some View {
        AnchoredActionConfirm(
            title: "Remove \(role.shortTitle)?",
            message: "\(name) will no longer be \(role.title). They keep their membership.",
            confirmTitle: "Remove",
            destructive: true,
            onConfirm: { remove(role) }
        ) {
            Text("Remove")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.warning)
        }
        .buttonStyle(.borderless)
        .disabled(isWorking)
        .accessibilityLabel("Remove \(role.title)")
    }

    private func remove(_ role: LeagueCoordinatorRole) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await appState.groupService.setCoordinator(
                    groupId: group.id,
                    role: role,
                    userId: nil
                )
                localError = nil
                PickemsHaptics.success()
            } catch {
                localError = UserFacingError.message(for: error, context: .write) ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }
}

/// Member picker for one coordinator seat. Each row confirms against that row.
struct CoordinatorMemberPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    let role: LeagueCoordinatorRole
    let group: PickemGroup
    let members: [GroupMember]
    let onChoose: (String) -> Void

    private var candidates: [GroupMember] {
        LeagueRolePolicy.candidates(for: role, group: group, members: members)
    }

    private var currentName: String? {
        guard let holder = LeagueRolePolicy.activeCoordinators(in: group).holder(of: role) else { return nil }
        return members.first { $0.id == holder }?.displayName
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text("No other members are available for this seat.")
                        .foregroundStyle(PickemsColors.textSecondary)
                        .listRowBackground(PickemsColors.cardBackground)
                } else {
                    ForEach(candidates) { member in
                        candidateRow(member)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle(role.shortTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func candidateRow(_ member: GroupMember) -> some View {
        let other = LeagueRolePolicy.activeRole(of: member.id, in: group)
        return AnchoredActionConfirm(
            title: appointTitle(member),
            message: appointMessage(member, other: other),
            confirmTitle: "Appoint",
            destructive: false,
            onConfirm: { onChoose(member.id) }
        ) {
            HStack(spacing: 12) {
                Text(member.displayName)
                    .foregroundStyle(PickemsColors.textPrimary)
                Spacer(minLength: 8)
                if let other {
                    LeagueRoleBadge(role: other)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(PickemsColors.cardBackground)
        .accessibilityLabel("Appoint \(member.displayName) as \(role.title)")
    }

    private func appointTitle(_ member: GroupMember) -> String {
        if currentName != nil {
            return "Replace \(role.shortTitle)?"
        }
        return "Appoint \(role.shortTitle)?"
    }

    private func appointMessage(_ member: GroupMember, other: LeagueCoordinatorRole?) -> String {
        if let other {
            return "\(member.displayName) is the \(other.shortTitle). They'll move to \(role.shortTitle) and that other seat opens."
        }
        if let currentName {
            return "\(member.displayName) replaces \(currentName) as \(role.title)."
        }
        return "\(member.displayName) becomes \(role.title) and can run the week if you're unavailable."
    }
}
