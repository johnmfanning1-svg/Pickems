import SwiftUI

/// Commissioner tool to remove, replace, or add Selections for a league member.
struct CommissionerManageSelectionsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let member: GroupMember
    let week: WeekSummary
    let groupId: String

    @State private var showBrowse = false
    @State private var replacing: Nomination?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var nominations: [Nomination] {
        appState.pickService.nominations.filter { $0.submittedBy == member.id }
    }

    private var perMember: Int {
        max(
            week.selectionsPerMember > 0
                ? week.selectionsPerMember
                : appState.groupService.selectedGroup?.rules.selectionsPerMember ?? 1,
            1
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Manage Selections for \(member.displayName)")
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)

                Text("Remove or replace their games, or add one if they still have a slot. This updates the slate for everyone.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)

                Text("\(nominations.count)/\(perMember) selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)

                if nominations.isEmpty {
                    ContentUnavailableView(
                        "No Selections",
                        systemImage: "american.football.fill",
                        description: Text("\(member.displayName) has not selected a game yet.")
                    )
                } else {
                    ForEach(nominations) { nom in
                        PickemsCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(nom.awayTeamName) @ \(nom.homeTeamName)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(PickemsColors.textPrimary)
                                HStack {
                                    Button {
                                        replacing = nom
                                        showBrowse = true
                                    } label: {
                                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    Spacer()
                                    Button("Remove", role: .destructive) {
                                        remove(nom)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .disabled(isWorking)
                            }
                        }
                    }
                }

                if nominations.count < perMember {
                    PrimaryButton(title: "Add Selection", isLoading: isWorking) {
                        replacing = nil
                        showBrowse = true
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(PickemsColors.warning)
                }
            }
            .padding()
        }
        .pickemsScreenBackground()
        .navigationTitle("Manage Selections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .sheet(isPresented: $showBrowse) {
            GameBrowseView(
                games: appState.picksViewModel.espnGames,
                nominatedEventIds: {
                    var ids = Set(
                        appState.pickService.nominations.map(\.espnEventId)
                            + appState.pickService.slateGames.map(\.espnEventId)
                    )
                    if let replacing {
                        ids.remove(replacing.espnEventId)
                    }
                    return ids
                }(),
                nominatorNamesByEventId: Dictionary(
                    appState.pickService.nominations.map { ($0.espnEventId, $0.submitterName) },
                    uniquingKeysWith: { first, _ in first }
                )
            ) { game in
                applyBrowse(game)
            }
            .pickemsEnvironment(appState)
        }
    }

    private func remove(_ nomination: Nomination) {
        guard let rules = appState.groupService.selectedGroup?.rules else { return }
        isWorking = true
        errorMessage = nil
        appState.picksViewModel.removeNomination(nomination, rules: rules, appState: appState)
        isWorking = false
        PickemsHaptics.success()
    }

    private func applyBrowse(_ game: ESPNGame) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                let rules = appState.groupService.selectedGroup?.rules ?? .default
                if let replacing {
                    try await appState.pickService.replaceNomination(
                        groupId: groupId,
                        weekId: week.id,
                        nomination: replacing,
                        game: game,
                        rules: rules,
                        week: week,
                        isCommissioner: true,
                        userId: appState.currentUserId ?? ""
                    )
                } else {
                    try await appState.pickService.submitNomination(
                        groupId: groupId,
                        weekId: week.id,
                        nomination: Nomination.fromESPNGame(
                            game,
                            submittedBy: member.id,
                            submitterName: member.displayName
                        ),
                        rules: rules,
                        week: week,
                        memberIds: appState.groupService.selectedGroup?.memberIds ?? [],
                        isCommissioner: true
                    )
                }
                self.replacing = nil
                showBrowse = false
                PickemsHaptics.success()
            } catch {
                errorMessage = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }
}
