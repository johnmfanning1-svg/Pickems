import SwiftUI

struct PickHistoryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            if let pick = appState.pickService.userPick {
                Section {
                    ForEach(appState.pickService.slateGames) { game in
                        PickResultRow(
                            game: game,
                            pickedTeamId: pick.picks[game.id],
                            homeRank: appState.picksViewModel.teamRanks.rank(for: game.homeTeamId),
                            awayRank: appState.picksViewModel.teamRanks.rank(for: game.awayTeamId)
                        )
                    }
                } header: {
                    Text("Your Picks")
                }

                if let submittedAt = pick.submittedAt {
                    Section {
                        Text("Submitted \(submittedAt.formatted())")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Picks Yet",
                    systemImage: "tray",
                    description: Text("Submit picks during the picking phase.")
                )
            }
        }
        .navigationTitle("This Week")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpInfoButton(topic: PickemsHelp.spreadPicks, size: .body)
            }
        }
        .task {
            await appState.picksViewModel.ensureTeamRanks(appState: appState)
        }
    }
}
