import SwiftUI

struct CreateGroupWizardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    @State private var step = 0
    @State private var groupName = ""
    @State private var rules = GroupRules.default
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var createdGroup: PickemGroup?

    var onComplete: () -> Void = {}

    var body: some View {
        NavigationStack {
            Group {
                if let createdGroup {
                    inviteStep(for: createdGroup)
                } else {
                    wizardContent
                }
            }
            .pickemsScreenBackground()
            .navigationTitle(createdGroup == nil ? "Create League" : "Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdGroup == nil ? "Cancel" : "Done") {
                        if createdGroup != nil {
                            finishAfterCreate()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var wizardContent: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: 3)
                .tint(theme.accent)
                .padding()

            TabView(selection: $step) {
                nameStep.tag(0)
                rulesStep.tag(1)
                reviewStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                Spacer()
                if step < 2 {
                    PrimaryButton(title: "Next") { step += 1 }
                        .frame(width: 120)
                        .disabled(step == 0 && groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    PrimaryButton(title: "Create League", isLoading: isWorking) {
                        create()
                    }
                    .frame(width: 160)
                }
            }
            .padding()
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name your league")
                .font(.title2.bold())
                .foregroundStyle(PickemsColors.textPrimary)
            Text("You'll be the commissioner and can invite friends with a code.")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)

            TextField("PPP Pickems", text: $groupName)
                .textFieldStyle(.pickems)

            HelpInfoButton(topic: PickemsHelp.createGroup)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rulesStep: some View {
        Form {
            Section {
                Picker("Mode", selection: $rules.selectionMode) {
                    ForEach(SelectionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if rules.selectionMode == .member {
                    Stepper(
                        "Nominations per member: \(rules.selectionsPerMember)",
                        value: $rules.selectionsPerMember,
                        in: 1...10
                    )
                } else {
                    Stepper("Games per week: \(rules.slateSize)", value: $rules.slateSize, in: 1...20)
                }
            } header: {
                Text("Selection")
            } footer: {
                Text(rules.selectionMode == .member
                    ? "Each member nominates this many games. The weekly slate size is members × nominations."
                    : "You choose every game for the group each week.")
            }
            Section {
                Picker("Tie breaker", selection: $rules.tieBreaker) {
                    ForEach(TieBreakerPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
            } header: {
                Text("Deadlines & Ties")
            } footer: {
                Text("Spread picks lock at the earliest game kickoff on the slate. You’ll set a nomination deadline each week.")
            }
        }
        .scrollContentBackground(.hidden)
        .onChange(of: rules.selectionMode) { _, mode in
            // Product rule: spread picks always lock at first kickoff.
            rules.pickDeadline = .firstKickoff
            if mode == .commissioner, rules.slateSize < 1 {
                rules.slateSize = 12
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review")
                .font(.title2.bold())
                .foregroundStyle(PickemsColors.textPrimary)

            PickemsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(groupName.isEmpty ? "My Pickems" : groupName)
                        .font(.headline)
                    Text(rules.selectionMode.displayName)
                    if rules.selectionMode == .member {
                        Text("\(rules.selectionsPerMember) nomination\(rules.selectionsPerMember == 1 ? "" : "s") per member")
                    } else {
                        Text("\(rules.slateSize) games per week")
                    }
                    Text("Picks lock at first kickoff")
                    Text("Tie-breaker: \(rules.tieBreaker.displayName)")
                }
                .foregroundStyle(PickemsColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(theme.accent)
            }

            Spacer()
        }
        .padding()
    }

    private func inviteStep(for group: PickemGroup) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)

                Text("\(group.name) is ready")
                    .font(.title2.bold())
                    .foregroundStyle(PickemsColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Share your invite code so friends can join.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            PickemsCard {
                VStack(spacing: 8) {
                    Text("Invite code")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                    Text(group.inviteCode)
                        .font(PickemsTypography.display(36))
                        .foregroundStyle(PickemsColors.textPrimary)
                        .tracking(4)
                        .textSelection(.enabled)
                        .accessibilityLabel("Invite code \(group.inviteCode)")
                }
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 12) {
                InviteShareButton(group: group)

                SecondaryButton("Skip for now") {
                    finishAfterCreate()
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    private func create() {
        Task {
            isWorking = true
            errorMessage = nil
            defer { isWorking = false }

            guard let user = await resolvedUser() else {
                errorMessage = "No signed-in user. Sign in to continue."
                AppLog.notice(AppLog.onboarding, "create league aborted — no profile", metadata: [
                    "signed_in": appState.authService.isSignedIn ? "true" : "false",
                    "uid": AppEvents.shortUID(appState.authService.currentUserId),
                ])
                return
            }
            do {
                rules.pickDeadline = .firstKickoff
                let group = try await appState.groupService.createGroup(
                    name: groupName.isEmpty ? "My Pickems" : groupName,
                    commissionerId: user.id,
                    displayName: user.displayName,
                    avatarColorHex: user.avatarColorHex,
                    avatarImageURL: user.avatarImageURL
                )
                try await appState.groupService.updateRules(groupId: group.id, rules: rules)
                appState.groupService.loadGroups(for: user.id)
                PickemsHaptics.success()
                // Show invite before dismissing so all entry points (incl. onboarding sheet) get the step.
                createdGroup = group
            } catch {
                errorMessage = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                AppLog.error(AppLog.onboarding, "create league wizard failed", error: error)
            }
        }
    }

    private func finishAfterCreate() {
        if let userId = appState.authService.currentUser?.id {
            appState.finishOnboarding(for: userId)
        }
        onComplete()
        dismiss()
    }

    private func resolvedUser() async -> UserProfile? {
        if let user = appState.authService.currentUser { return user }
        await appState.authService.refreshSession()
        if let user = appState.authService.currentUser { return user }

        #if DEBUG
        if DevAuthBypass.isEnabled {
            await appState.authService.activateDevBypass()
        }
        #endif

        return appState.authService.currentUser
    }
}
