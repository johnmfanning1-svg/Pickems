import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var inviteCode = ""
    @State private var mode: OnboardingMode = .join
    @State private var isWorking = false
    @State private var localError: String?
    @State private var showCreateWizard = false

    enum OnboardingMode: String, CaseIterable {
        case join = "Join Group"
        case create = "Create Group"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Image(systemName: "football.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(theme.accent)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityHidden(true)

                        Text("Welcome, \(appState.authService.currentUser?.displayName ?? "Player")!")
                            .font(.title2.bold())
                            .foregroundStyle(PickemsColors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("Join a league or start your own pick'em group.")
                            .font(.subheadline)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    Picker("Mode", selection: $mode) {
                        ForEach(OnboardingMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Join or create a group")

                    if mode == .join {
                        joinSection
                    } else {
                        createSection
                    }

                    if isWorking {
                        ProgressView()
                            .tint(theme.accent)
                            .accessibilityLabel("Working")
                    }

                    if let error = localError ?? appState.groupService.errorMessage ?? appState.authService.errorMessage {
                        ContextualTipBanner(
                            icon: "exclamationmark.triangle.fill",
                            message: error
                        )
                    }
                }
                .padding()
            }
            .pickemsScreenBackground()
            .navigationTitle("Get Started")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCreateWizard) {
                CreateGroupWizardView()
            }
            .onAppear {
                if let pending = appState.pendingInviteCode, !pending.isEmpty {
                    inviteCode = pending
                    mode = .join
                }
            }
        }
    }

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Invite Code")
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)
                Spacer()
                HelpInfoButton(topic: PickemsHelp.joinGroup, size: .subheadline)
            }

            TextField("6-character code", text: $inviteCode)
                .textFieldStyle(.pickems)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityLabel("Invite code")

            PrimaryButton(
                title: "Join Group",
                isLoading: isWorking,
                accessibilityHint: "Join a league using the invite code from your commissioner"
            ) {
                joinGroup()
            }
        }
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up your league with a guided wizard — name, rules, slate size, and deadlines.")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)

            PrimaryButton(title: "Start League Wizard") {
                showCreateWizard = true
            }
        }
    }

    private func joinGroup() {
        Task {
            isWorking = true
            localError = nil
            defer { isWorking = false }

            guard let user = await resolvedUser() else {
                localError = "No signed-in user. Sign in with Apple to continue."
                return
            }
            do {
                try await appState.joinGroup(inviteCode: inviteCode, markOnboarding: true)
                PickemsHaptics.success()
            } catch {
                localError = error.localizedDescription
            }
        }
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
