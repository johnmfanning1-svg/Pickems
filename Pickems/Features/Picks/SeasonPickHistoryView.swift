import SwiftUI

struct SeasonPickHistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var entries: [WeekHistoryEntry] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(PickemsColors.cardBackground)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Past weeks appear here after games are scored.")
                )
            } else {
                ForEach(entries) { entry in
                    NavigationLink {
                        WeekHistoryDetailView(entry: entry)
                    } label: {
                        WeekHistoryRow(entry: entry)
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                }
            }
        }
        .navigationTitle("Season History")
        .navigationBarTitleDisplayMode(.large)
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpInfoButton(topic: PickemsHelp.picksOverview, size: .body)
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let group = appState.groupService.selectedGroup,
              let userId = appState.authService.currentUser?.id else { return }

        do {
            let weeks = try await appState.groupService.fetchPastWeeks(groupId: group.id)
            var loaded: [WeekHistoryEntry] = []
            for week in weeks where week.status == .scored || week.status == .locked {
                if let entry = try await appState.pickService.loadWeekHistory(
                    groupId: group.id,
                    weekId: week.id,
                    userId: userId
                ) {
                    loaded.append(entry)
                }
            }
            entries = loaded.sorted { $0.week.weekNumber > $1.week.weekNumber }
        } catch {
            entries = []
        }
    }
}

struct WeekHistoryRow: View {
    let entry: WeekHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.week.displayLabel)
                .font(.headline)
                .foregroundStyle(PickemsColors.textPrimary)
            if let pick = entry.userPick {
                let record = ScoringEngine.scorePicks(picks: pick.picks, games: entry.slateGames)
                Text("\(record.wins)-\(record.losses) · \(entry.slateGames.count) games")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            } else {
                Text("No picks submitted")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WeekHistoryDetailView: View {
    let entry: WeekHistoryEntry

    var body: some View {
        List {
            Section(entry.week.displayLabel) {
                if let pick = entry.userPick {
                    ForEach(entry.slateGames) { game in
                        PickResultRow(game: game, pickedTeamId: pick.picks[game.id])
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .navigationTitle("Week \(entry.week.weekNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
