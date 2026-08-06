import SwiftUI

struct CommissionerSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    let group: PickemGroup
    @State private var rules: GroupRules
    @State private var isPublic: Bool
    @State private var groupName: String
    @State private var isSaving = false
    @State private var showCloseSeasonConfirm = false
    @State private var closeSeasonError: String?

    @State private var isEditingCode = false
    @State private var customCode = ""
    @State private var isUpdatingCode = false
    @State private var identityError: String?
    @State private var memberToRemove: GroupMember?
    @State private var memberActionError: String?
    @State private var memberToPromote: GroupMember?
    @State private var showDeleteLeagueConfirm = false
    @State private var isWorkingMembers = false

    @FocusState private var codeFieldFocused: Bool

    init(group: PickemGroup) {
        self.group = group
        _rules = State(initialValue: group.rules)
        _isPublic = State(initialValue: group.isPublic)
        _groupName = State(initialValue: group.name)
    }

    private var liveGroup: PickemGroup {
        appState.groupService.selectedGroup?.id == group.id
            ? (appState.groupService.selectedGroup ?? group)
            : group
    }

    private var otherMembers: [GroupMember] {
        appState.groupService.members
            .filter { $0.id != liveGroup.commissionerId }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var seasonYearToClose: Int {
        appState.groupService.cfbWeek?.seasonYear
            ?? appState.groupService.currentWeek?.seasonYear
            ?? Calendar.current.component(.year, from: Date())
    }

    private var seasonAlreadyClosed: Bool {
        appState.groupService.seasonArchives.contains { $0.seasonYear == seasonYearToClose }
    }

    var body: some View {
        NavigationStack {
            Form {
                leagueIdentitySection
                membersSection

                Section {
                    Picker("Who selects games", selection: $rules.selectionMode) {
                        ForEach(SelectionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .listRowBackground(PickemsColors.cardBackground)

                    if rules.selectionMode == .member {
                        Stepper(
                            "Nominations per member: \(rules.selectionsPerMember)",
                            value: $rules.selectionsPerMember,
                            in: 1...10
                        )
                        .listRowBackground(PickemsColors.cardBackground)
                    } else {
                        Stepper("Games per week: \(rules.slateSize)", value: $rules.slateSize, in: 1...20)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                } header: {
                    sectionHeader("Slate Configuration", help: PickemsHelp.commissionerSettings)
                } footer: {
                    Text(rules.selectionMode == .member
                        ? "Each member nominates this many games. Weekly game target = members × nominations. You’ll set a nomination deadline each week."
                        : "You choose every game for the group each week.")
                }

                Section {
                    LabeledContent("Pick deadline", value: "First game kickoff")
                        .listRowBackground(PickemsColors.cardBackground)

                    Picker("Tie breaker", selection: $rules.tieBreaker) {
                        ForEach(TieBreakerPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .listRowBackground(PickemsColors.cardBackground)

                    Toggle("Confidence pick (2x one game)", isOn: $rules.allowConfidencePick)
                        .listRowBackground(PickemsColors.cardBackground)
                    Toggle("Allow late picks", isOn: $rules.allowLatePicks)
                        .listRowBackground(PickemsColors.cardBackground)
                    if rules.allowLatePicks {
                        Stepper(
                            "Late penalty: \(rules.latePickPenaltyWins) win(s)",
                            value: $rules.latePickPenaltyWins,
                            in: 1...3
                        )
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                } header: {
                    sectionHeader("Deadlines & Ties", help: PickemsHelp.pickDeadline)
                } footer: {
                    Text("Spread picks lock at the earliest kickoff on the slate. Changes apply to future weeks.")
                }

                Section {
                    Toggle("List in Discover", isOn: $isPublic)
                        .listRowBackground(PickemsColors.cardBackground)
                    NavigationLink {
                        SubmissionStatusView(
                            members: appState.groupService.members,
                            submissions: appState.pickService.submissions,
                            slateSize: appState.pickService.slateGames.count
                        )
                    } label: {
                        Label("Submission chase", systemImage: "person.crop.circle.badge.clock")
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                } header: {
                    Text("Visibility & Chase")
                } footer: {
                    Text("Public leagues appear in Discover. Submission chase shows who still needs to lock picks.")
                }

                Section {
                    if seasonAlreadyClosed {
                        LabeledContent("Season \(seasonYearToClose.pickemsYearString)", value: "Archived")
                            .listRowBackground(PickemsColors.cardBackground)
                    } else {
                        Button(role: .destructive) {
                            showCloseSeasonConfirm = true
                        } label: {
                            if appState.groupService.isClosingSeason {
                                HStack {
                                    ProgressView()
                                    Text("Closing Season \(seasonYearToClose.pickemsYearString)…")
                                }
                            } else {
                                Label("Close Season \(seasonYearToClose.pickemsYearString)", systemImage: "trophy.fill")
                            }
                        }
                        .disabled(appState.groupService.isClosingSeason)
                        .listRowBackground(PickemsColors.cardBackground)
                    }

                    if let closeSeasonError {
                        Text(closeSeasonError)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                } header: {
                    Text("Dynasty")
                } footer: {
                    Text("Archives final standings and resets season W–L. Auto-close also runs mid-January via Cloud Functions.")
                }
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle("Commissioner Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
            .confirmationDialog(
                "Close Season \(seasonYearToClose.pickemsYearString)?",
                isPresented: $showCloseSeasonConfirm,
                titleVisibility: .visible
            ) {
                Button("Close Season", role: .destructive) { closeSeason() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This archives \(seasonYearToClose.pickemsYearString) standings and resets everyone’s season record. This cannot be undone.")
            }
            .confirmationDialog(
                "Remove \(memberToRemove?.displayName ?? "member")?",
                isPresented: Binding(
                    get: { memberToRemove != nil },
                    set: { if !$0 { memberToRemove = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Member", role: .destructive) {
                    if let member = memberToRemove { removeMember(member) }
                    memberToRemove = nil
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            } message: {
                Text("They lose access to this league’s picks and standings. They can rejoin with the invite code.")
            }
            .confirmationDialog(
                "Make \(memberToPromote?.displayName ?? "member") the commissioner?",
                isPresented: Binding(
                    get: { memberToPromote != nil },
                    set: { if !$0 { memberToPromote = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Transfer Commissioner", role: .destructive) {
                    if let member = memberToPromote { transferCommissioner(to: member) }
                    memberToPromote = nil
                }
                Button("Cancel", role: .cancel) { memberToPromote = nil }
            } message: {
                Text("You become a regular member. Only one commissioner is allowed at a time.")
            }
            .confirmationDialog(
                "Delete this league permanently?",
                isPresented: $showDeleteLeagueConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete League", role: .destructive) { deleteLeague() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the league, invite code, members, picks, standings, and season history for everyone. This cannot be undone.")
            }
        }
    }

    private var leagueIdentitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("League name")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                TextField("League name", text: $groupName)
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(PickemsColors.textPrimary)
            }
            .listRowBackground(PickemsColors.cardBackground)

            if isEditingCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite code")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                    TextField("ABCD12", text: $customCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($codeFieldFocused)
                        .onChange(of: customCode) { _, newValue in
                            customCode = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
                        }
                        .foregroundStyle(PickemsColors.textPrimary)
                    HStack {
                        Button("Save Code") { saveCustomCode() }
                            .buttonStyle(.borderless)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.accent)
                            .disabled(isUpdatingCode || customCode.count < 4)
                        Spacer()
                        Button("Cancel") {
                            isEditingCode = false
                            codeFieldFocused = false
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(PickemsColors.textSecondary)
                    }
                    Text("4–8 letters or numbers. Members join with this code.")
                        .font(.caption2)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .listRowBackground(PickemsColors.cardBackground)
            } else {
                LabeledContent("Invite code", value: liveGroup.inviteCode)
                    .listRowBackground(PickemsColors.cardBackground)

                Button {
                    customCode = liveGroup.inviteCode
                    isEditingCode = true
                    codeFieldFocused = true
                } label: {
                    Label("Set Custom Code", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.accent)
                .listRowBackground(PickemsColors.cardBackground)

                Button {
                    regenerateCode()
                } label: {
                    if isUpdatingCode {
                        HStack { ProgressView(); Text("Rolling new code…") }
                    } else {
                        Label("Regenerate Code", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.accent)
                .disabled(isUpdatingCode)
                .listRowBackground(PickemsColors.cardBackground)
            }

            if let identityError {
                Text(identityError)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.warning)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("League Identity")
        } footer: {
            Text("Rename the league or change the invite code any time. The old code stops working once you change it.")
        }
    }

    @ViewBuilder
    private var membersSection: some View {
        Section {
            if otherMembers.isEmpty {
                Text("No other members yet. Share your invite code to grow the league.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            } else {
                ForEach(otherMembers) { member in
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
                        .disabled(isWorkingMembers)

                        Button(role: .destructive) {
                            memberToRemove = member
                        } label: {
                            Image(systemName: "person.badge.minus")
                                .foregroundStyle(PickemsColors.warning)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(member.displayName)")
                        .disabled(isWorkingMembers)
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                }

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
                .disabled(isWorkingMembers)
            }

            Button(role: .destructive) {
                showDeleteLeagueConfirm = true
            } label: {
                Label("Delete League", systemImage: "trash")
            }
            .listRowBackground(PickemsColors.cardBackground)
            .disabled(isWorkingMembers)

            if let memberActionError {
                Text(memberActionError)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.warning)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("Members & Ownership")
        } footer: {
            Text("Remove members, transfer commissioner (one at a time), or delete the entire league. Deleting erases all picks and standings.")
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, help: HelpTopic? = nil) -> some View {
        HStack {
            Text(title)
            if let help {
                Spacer()
                HelpInfoButton(topic: help, size: .caption)
            }
        }
    }

    private func save() {
        isSaving = true
        rules.pickDeadline = .firstKickoff
        Task {
            do {
                let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedName != liveGroup.name {
                    try await appState.groupService.renameGroup(groupId: group.id, name: trimmedName)
                }
                try await appState.groupService.updateRules(groupId: group.id, rules: rules)
                try await appState.groupService.setPublic(groupId: group.id, isPublic: isPublic)
                PickemsHaptics.success()
                dismiss()
            } catch {
                UserFacingError.apply(error, to: &appState.groupService.errorMessage, context: .write)
                identityError = UserFacingError.message(for: error, context: .write)
                    ?? "Couldn't save those settings."
            }
            isSaving = false
        }
    }

    private func saveCustomCode() {
        identityError = nil
        isUpdatingCode = true
        Task {
            do {
                try await appState.groupService.updateInviteCode(groupId: group.id, newCode: customCode)
                PickemsHaptics.success()
                isEditingCode = false
                codeFieldFocused = false
            } catch {
                identityError = error.localizedDescription
                PickemsHaptics.warning()
            }
            isUpdatingCode = false
        }
    }

    private func regenerateCode() {
        identityError = nil
        isUpdatingCode = true
        Task {
            do {
                try await appState.groupService.regenerateInviteCode(groupId: group.id)
                PickemsHaptics.success()
            } catch {
                identityError = error.localizedDescription
                PickemsHaptics.warning()
            }
            isUpdatingCode = false
        }
    }

    private func removeMember(_ member: GroupMember) {
        memberActionError = nil
        isWorkingMembers = true
        Task {
            defer { isWorkingMembers = false }
            do {
                try await appState.groupService.removeMember(groupId: group.id, userId: member.id)
                PickemsHaptics.success()
            } catch {
                memberActionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func transferCommissioner(to member: GroupMember) {
        memberActionError = nil
        isWorkingMembers = true
        Task {
            defer { isWorkingMembers = false }
            do {
                try await appState.groupService.transferCommissioner(groupId: group.id, toUserId: member.id)
                PickemsHaptics.success()
                dismiss()
            } catch {
                memberActionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func deleteLeague() {
        memberActionError = nil
        isWorkingMembers = true
        Task {
            defer { isWorkingMembers = false }
            do {
                try await appState.groupService.deleteGroup(groupId: group.id)
                PickemsHaptics.success()
                dismiss()
            } catch {
                memberActionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func closeSeason() {
        closeSeasonError = nil
        Task {
            do {
                try await appState.groupService.closeSeason(groupId: group.id, seasonYear: seasonYearToClose)
                PickemsHaptics.success()
            } catch {
                closeSeasonError = error.localizedDescription
            }
        }
    }

}
