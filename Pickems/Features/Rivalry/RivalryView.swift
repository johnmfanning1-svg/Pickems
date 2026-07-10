import SwiftUI

struct RivalryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var opponentId: String?
    @State private var result: RivalryEngine.HeadToHead?
    @State private var isLoading = false

    private var members: [GroupMember] {
        appState.groupService.members.filter { $0.id != appState.authService.currentUser?.id }
    }

    var body: some View {
        List {
            Section {
                Picker("Opponent", selection: $opponentId) {
                    Text("Select…").tag(String?.none)
                    ForEach(members) { member in
                        Text(member.displayName).tag(Optional(member.id))
                    }
                }
                .listRowBackground(PickemsColors.cardBackground)
            } header: {
                Text("Head-to-Head")
            } footer: {
                Text("Compares weekly W–L across scored weeks this season.")
            }

            if isLoading {
                ProgressView()
                    .listRowBackground(PickemsColors.cardBackground)
            } else if let result {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.summary)
                            .font(PickemsTypography.display(22))
                            .foregroundStyle(theme.accent)
                        Text("You \(result.userAWins) · Them \(result.userBWins) · Ties \(result.ties)")
                            .font(.subheadline)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .navigationTitle("Rivalry")
        .onChange(of: opponentId) { _, newValue in
            guard let newValue else { return }
            Task { await load(opponentId: newValue) }
        }
    }

    private func load(opponentId: String) async {
        guard let group = appState.groupService.selectedGroup,
              let me = appState.authService.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }

        let weeks = (try? await appState.groupService.fetchPastWeeks(groupId: group.id, limit: 20)) ?? []
        var rows: [(weekId: String, aWins: Int, aLosses: Int, bWins: Int, bLosses: Int)] = []
        for week in weeks where week.status == .scored {
            let a = try? await appState.groupService.loadPlayerSeasonStats(groupId: group.id, userId: me)
            // Use week-specific scoring from picks
            let historyA = try? await appState.pickService.loadWeekHistory(groupId: group.id, weekId: week.id, userId: me)
            let historyB = try? await appState.pickService.loadWeekHistory(groupId: group.id, weekId: week.id, userId: opponentId)
            guard let historyA, let historyB,
                  let pickA = historyA.userPick,
                  let pickB = historyB.userPick else { continue }
            let scoreA = ScoringEngine.scorePicks(picks: pickA.picks, games: historyA.slateGames)
            let scoreB = ScoringEngine.scorePicks(picks: pickB.picks, games: historyB.slateGames)
            rows.append((week.id, scoreA.wins, scoreA.losses, scoreB.wins, scoreB.losses))
            _ = a
        }
        result = RivalryEngine.headToHead(userAId: me, userBId: opponentId, weekResults: rows)
    }
}
