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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Force Pickems for \(member.displayName)")
                        .font(.headline)
                        .foregroundStyle(PickemsColors.textPrimary)

                    Text("Choose a side for each slate game, or clear their Pickems entirely. This never removes Selections from the slate.")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)

                    if slateGames.isEmpty {
                        ContentUnavailableView(
                            "No Slate Games",
                            systemImage: "american.football.fill",
                            description: Text("Add games to the slate before forcing Pickems.")
                        )
                    } else {
                        ForEach(slateGames) { game in
                            GamePickRow(
                                game: game,
                                selectedTeamId: draftPicks[game.id],
                                showConfidenceToggle: false
                            ) { teamId in
                                if teamId.isEmpty {
                                    draftPicks.removeValue(forKey: game.id)
                                } else {
                                    draftPicks[game.id] = teamId
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                    }

                    PrimaryButton(title: "Save Forced Pickems", isLoading: isWorking) {
                        save(isLocked: true)
                    }
                    .disabled(slateGames.isEmpty || draftPicks.count < slateGames.count || isWorking)
                    if !slateGames.isEmpty, draftPicks.count < slateGames.count {
                        Text("Pick a side for every game (\(draftPicks.count)/\(slateGames.count)) before saving.")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }

                    SecondaryButton("Save as Draft (not submitted)", icon: "pencil") {
                        save(isLocked: false)
                    }
                    .disabled(slateGames.isEmpty || draftPicks.isEmpty || isWorking)

                    Button("Clear All Pickems", role: .destructive) {
                        showClearConfirm = true
                    }
                    .disabled(isWorking)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .pickemsScreenBackground()
            .navigationTitle("Manage Pickems")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(
                "Clear Pickems for \(member.displayName)?",
                isPresented: $showClearConfirm
            ) {
                Button("Clear Pickems", role: .destructive) { clearPicks() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their spread Pickems and submitted status for this week will be wiped. Slate Selections stay.")
            }
            .task {
                await appState.pickService.loadAllPicks(groupId: groupId, weekId: week.id)
                if draftPicks.isEmpty {
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
