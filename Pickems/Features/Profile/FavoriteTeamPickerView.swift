import SwiftUI

struct FavoriteTeamPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var isOnboardingPrompt: Bool = false

    @State private var searchText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selectedTeam: FavoriteTeam? {
        appState.authService.currentUser?.favoriteTeam
    }

    private var teams: [FavoriteTeam] {
        TeamThemeCatalog.team(matching: searchText)
            .filter { $0.id != selectedTeam?.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if isOnboardingPrompt {
                    Section {
                        Text("Pick your team and Pickems will theme accents and atmosphere around your colors.")
                            .font(.subheadline)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                }

                if let selectedTeam {
                    Section {
                        FavoriteTeamRow(team: selectedTeam, isSelected: true)
                            .listRowBackground(PickemsColors.cardBackground)

                        Button(role: .destructive) {
                            clearSelection()
                        } label: {
                            Label("Clear favorite team", systemImage: "xmark.circle")
                        }
                        .listRowBackground(PickemsColors.cardBackground)
                        .accessibilityHint("Removes your team theme and uses the default Pickems look")
                    } header: {
                        Text("Current Team")
                    }
                } else if !isOnboardingPrompt {
                    Section {
                        Button {
                            clearSelection()
                        } label: {
                            Label("Using default Pickems theme", systemImage: "paintbrush")
                        }
                        .disabled(true)
                        .listRowBackground(PickemsColors.cardBackground)
                    } header: {
                        Text("Current Team")
                    }
                }

                Section {
                    ForEach(teams) { team in
                        Button {
                            select(team)
                        } label: {
                            FavoriteTeamRow(team: team, isSelected: false)
                        }
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                } header: {
                    Text("College Football Teams")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle(isOnboardingPrompt ? "Pick Your Team" : "Favorite Team")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search teams")
            .toolbar {
                if isOnboardingPrompt {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Later") {
                            if let userId = appState.authService.currentUserId {
                                appState.authService.markFavoriteTeamPromptDismissed(for: userId)
                            }
                            dismiss()
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    if selectedTeam != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Clear") { clearSelection() }
                                .foregroundStyle(PickemsColors.warning)
                        }
                    }
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView()
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func select(_ team: FavoriteTeam) {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await appState.authService.updateFavoriteTeam(team)
                appState.appTheme.apply(team: team)
                PickemsHaptics.success()
                if isOnboardingPrompt, let userId = appState.authService.currentUserId {
                    appState.authService.markFavoriteTeamPromptDismissed(for: userId)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearSelection() {
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                try await appState.authService.updateFavoriteTeam(nil)
                appState.appTheme.apply(team: nil)
                PickemsHaptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct FavoriteTeamRow: View {
    let team: FavoriteTeam
    let isSelected: Bool

    private var palette: ThemePalette { .from(team: team) }
    private var primaryOnFill: Color {
        ColorContrast.onAccent(for: ColorContrast.RGB.from(hex: team.primaryHex)).color
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(team.primaryColor)
                    .frame(width: 40, height: 40)
                if let url = URL(string: team.resolvedLogoURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        default:
                            Text(team.abbreviation)
                                .font(.caption2.bold())
                                .foregroundStyle(primaryOnFill)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(team.abbreviation)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle().fill(team.primaryColor).frame(width: 12, height: 12)
                Circle().fill(team.secondaryColor).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(team.name), \(team.abbreviation)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
