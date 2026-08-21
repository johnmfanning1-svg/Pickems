import SwiftUI

/// Full-screen Scrimmage tutorial: a local, simulated practice week that
/// teaches the pick'em rhythm without touching real records or Firestore.
struct ScrimmageView: View {
    let context: ScrimmageContext

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    @State private var engine: ScrimmageEngine?

    var body: some View {
        NavigationStack {
            Group {
                if let engine {
                    phaseContent(engine)
                } else {
                    ProgressView()
                        .tint(theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading scrimmage")
                }
            }
            .pickemsScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 4) {
                        Text("Scrimmage")
                            .font(.headline)
                            .foregroundStyle(PickemsColors.textPrimary)
                        StatusBadge(text: ScrimmageDefaults.leagueName, color: theme.accent)
                    }
                    .accessibilityElement(children: .combine)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Skip scrimmage")
                    .accessibilityHint("Closes the practice week immediately")
                }
            }
        }
        .task {
            guard engine == nil else { return }
            let raw = appState.authService.currentUser?.displayName ?? "You"
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            engine = ScrimmageEngine(userDisplayName: trimmed.isEmpty ? "You" : trimmed)
        }
    }

    @ViewBuilder
    private func phaseContent(_ engine: ScrimmageEngine) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                phaseBody(engine)
                    .id(engine.phase)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
            }
            .padding(.vertical)
            .animation(.easeInOut(duration: 0.32), value: engine.phase)
        }
        .onChange(of: engine.phase) { _, newPhase in
            handlePhaseHaptics(newPhase)
        }
    }

    @ViewBuilder
    private func phaseBody(_ engine: ScrimmageEngine) -> some View {
        switch engine.phase {
        case .intro:
            ScrimmageIntroPhase {
                withAnimation {
                    engine.advance()
                }
            }

        case .picking:
            ScrimmagePickingPhase(
                games: engine.games,
                draftPicks: engine.draftPicks,
                allPicksMade: engine.allPicksMade,
                onSelect: { gameId, teamId in
                    engine.selectTeam(gameId: gameId, teamId: teamId)
                },
                onSubmit: {
                    engine.submitPicks()
                    Task { await engine.runLiveSimulation() }
                }
            )

        case .locked, .live:
            ScrimmageLivePhase(
                phase: engine.phase,
                games: engine.games,
                draftPicks: engine.draftPicks
            )

        case .results:
            ScrimmageResultsPhase(
                games: engine.games,
                draftPicks: engine.draftPicks,
                userRecord: engine.userRecord,
                onContinue: {
                    withAnimation {
                        engine.advance()
                    }
                }
            )

        case .standings:
            ScrimmageStandingsPhase(
                standings: engine.standings,
                onContinue: {
                    withAnimation {
                        engine.advance()
                    }
                }
            )

        case .celebration:
            ScrimmageCelebrationPhase(
                context: context,
                userRecord: engine.userRecord,
                onFinish: {
                    UserDefaults.standard.set(true, forKey: ScrimmageDefaults.completedKey)
                    dismiss()
                },
                onReplay: {
                    withAnimation {
                        engine.reset()
                    }
                }
            )
        }
    }

    private func handlePhaseHaptics(_ phase: ScrimmagePhase) {
        switch phase {
        case .locked:
            PickemsHaptics.warning()
        case .results:
            PickemsHaptics.success()
        case .standings:
            PickemsHaptics.lightImpact()
        case .intro, .picking, .live, .celebration:
            // Celebration plays its own success haptic with the trophy entrance.
            break
        }
    }
}
