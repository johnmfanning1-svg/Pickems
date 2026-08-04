import SwiftUI

/// Commissioner tool to wipe or force-select picks for a league member.
struct CommissionerManagePicksSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let member: GroupMember
    let week: WeekSummary
    let groupId: String
    let slateGames: [SlateGame]

    @State private var draftPicks: [String: String] = [:]
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Force picks for \(member.displayName)")
                        .font(.headline)
                        .foregroundStyle(PickemsColors.textPrimary)

                    Text("Choose a side for each slate game, or clear their picks entirely.")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)

                    if slateGames.isEmpty {
                        ContentUnavailableView(
                            "No Slate Games",
                            systemImage: "sportscourt",
                            description: Text("Add games to the slate before forcing picks.")
                        )
                    } else {
                        ForEach(slateGames) { game in
                            GamePickRow(
                                game: game,
                                selectedTeamId: draftPicks[game.id],
                                showConfidenceToggle: false
                            ) { teamId in
                                draftPicks[game.id] = teamId
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                    }

                    PrimaryButton(title: "Save Forced Picks", isLoading: isWorking) {
                        save(isLocked: true)
                    }
                    .disabled(slateGames.isEmpty || draftPicks.count < slateGames.count || isWorking)

                    SecondaryButton("Save as Draft (not submitted)", icon: "pencil") {
                        save(isLocked: false)
                    }
                    .disabled(slateGames.isEmpty || draftPicks.isEmpty || isWorking)

                    Button("Clear All Picks", role: .destructive) {
                        showClearConfirm = true
                    }
                    .disabled(isWorking)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .pickemsScreenBackground()
            .navigationTitle("Manage Picks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                "Clear picks for \(member.displayName)?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Picks", role: .destructive) { clearPicks() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their picks and submitted status for this week will be wiped.")
            }
            .onAppear {
                if let existing = appState.pickService.allPicks.first(where: { $0.userId == member.id }) {
                    draftPicks = existing.picks
                } else if let own = appState.pickService.userPick, own.userId == member.id {
                    draftPicks = own.picks
                }
            }
        }
    }

    private func save(isLocked: Bool) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await appState.pickService.commissionerSetPicks(
                    groupId: groupId,
                    weekId: week.id,
                    userId: member.id,
                    displayName: member.displayName,
                    picks: draftPicks,
                    isLocked: isLocked
                )
                PickemsHaptics.success()
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func clearPicks() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await appState.pickService.commissionerClearPicks(
                    groupId: groupId,
                    weekId: week.id,
                    userId: member.id,
                    displayName: member.displayName
                )
                draftPicks = [:]
                PickemsHaptics.success()
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }
}
