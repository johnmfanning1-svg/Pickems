import SwiftUI

struct GroupPicksView: View {
    @Environment(AppState.self) private var appState

    private var submittedPicks: [UserPick] {
        appState.pickService.allPicks.filter(\.isLocked)
    }

    var body: some View {
        List {
            if submittedPicks.isEmpty {
                ContentUnavailableView(
                    "No Submitted Picks",
                    systemImage: "tray",
                    description: Text("Picks appear here once members submit.")
                )
            } else {
                ForEach(submittedPicks) { pick in
                    Section(pick.displayName) {
                        ForEach(appState.pickService.slateGames) { game in
                            PickResultRow(game: game, pickedTeamId: pick.picks[game.id])
                        }
                    }
                }
            }
        }
        .navigationTitle("Group Picks")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
    }
}
