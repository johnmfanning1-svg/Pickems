import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var inviteCode = ""
    @State private var mode: OnboardingMode = .join
    @State private var isWorking = false
    @State private var localError: String?
    @State private var showScrimmage = false

    enum OnboardingMode: String, CaseIterable {
        case join = "Join League"
        case create = "Create League"
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

                        Text("Join a league or start your own pick'em league.")
                            .font(.subheadline)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    favoriteTeamSection

                    stayOnTimeSection

                    SecondaryButton("Try a Scrimmage first", icon: "figure.american.football") {
                        showScrimmage = true
                    }
                    .accessibilityHint("Practice Selections and Pickems with a fake week before joining")

                    Picker("Mode", selection: $mode) {
                        ForEach(OnboardingMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Join or create a league")

                    if mode == .join {
                        joinSection
                    } else {
                        createSection
                    }

                    SecondaryButton("Skip for now") {
                        skipOnboarding()
                    }
                    .accessibilityHint("Continue to the app without joining a league")

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
            .fullScreenCover(isPresented: $showScrimmage) {
                ScrimmageView(context: .onboarding)
                    .pickemsEnvironment(appState)
            }
            .onAppear {
                if let pending = appState.pendingInviteCode, !pending.isEmpty {
                    inviteCode = pending
                    mode = .join
                }
            }
        }
    }

    private var favoriteTeamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorite Team")
                .font(.headline)
                .foregroundStyle(PickemsColors.textPrimary)

            Button {
                appState.present(.favoriteTeam(isOnboardingPrompt: false))
            } label: {
                HStack(spacing: 12) {
                    if let team = appState.authService.currentUser?.favoriteTeam {
                        ZStack {
                            Circle()
                                .fill(team.primaryColor)
                                .frame(width: 36, height: 36)
                            if let url = URL(string: team.resolvedLogoURL) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFit()
                                    }
                                }
                                .frame(width: 24, height: 24)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.name)
                                .foregroundStyle(PickemsColors.textPrimary)
                            Text("Tap to change")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                    } else {
                        Label("Choose your team", systemImage: "shield.lefthalf.filled")
                            .foregroundStyle(theme.accent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .padding(14)
                .background(PickemsColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the favorite team picker")
        }
    }

    private var stayOnTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stay on time")
                .font(.headline)
                .foregroundStyle(PickemsColors.textPrimary)
            Text("Allow notifications for deadlines, game results, and chat. You can choose which alerts you get later in Profile.")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
            Button {
                Task {
                    await appState.notificationService.requestPermission()
                    if let uid = appState.currentUserId {
                        appState.authService.markNotificationOnboardingDismissed(for: uid)
                        await appState.notificationService.saveToken(for: uid)
                    }
                }
            } label: {
                Label("Allow notifications", systemImage: "bell.badge.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
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

            TextField("4–8 character code", text: $inviteCode)
                .textFieldStyle(.pickems)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityLabel("Invite code")

            PrimaryButton(
                title: "Join League",
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
                appState.present(.createLeague)
            }
        }
    }

    private func joinGroup() {
        Task {
            isWorking = true
            localError = nil
            defer { isWorking = false }

            guard let user = await resolvedUser() else {
                localError = "No signed-in user. Sign in to continue."
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

    private func skipOnboarding() {
        Task {
            guard let user = await resolvedUser() else {
                localError = "No signed-in user. Sign in to continue."
                return
            }
            appState.finishOnboarding(for: user.id)
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
