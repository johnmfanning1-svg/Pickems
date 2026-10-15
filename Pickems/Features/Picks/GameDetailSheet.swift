import SwiftUI

/// One slate game, presented from the app sheet host.
/// Same pick row Pickems and Selections use, with the final score when we have it.
struct GameDetailSheet: View {
    let gameId: String
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                detail
                    .padding(.vertical)
            }
            .navigationTitle("Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .pickemsScreenBackground()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let game = matchingGame {
            gameCard(game)
        } else if let veto = matchingVeto {
            vetoCard(veto)
        } else if slateSettled {
            ContentUnavailableView(
                "Game unavailable",
                systemImage: "sportscourt",
                description: Text("That game isn't on this week's slate.")
            )
        } else {
            ProgressView("Loading game")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .accessibilityLabel("Loading game")
        }
    }

    private var matchingGame: SlateGame? {
        if let game = appState.pickService.slateGames.first(where: { $0.id == gameId || $0.espnEventId == gameId }) {
            return game
        }
        return appState.pickService.nominations
            .first { $0.id == gameId || $0.espnEventId == gameId }?
            .asSlateGame()
    }

    private var matchingVeto: SelectionVeto? {
        appState.pickService.vetoes.first { $0.id == gameId || $0.espnEventId == gameId }
    }

    /// The focused week has delivered its slate, nominations, and veto records.
    private var slateSettled: Bool {
        guard let weekId = appState.focusedWeekId else { return false }
        guard appState.groupService.currentWeek?.id == weekId else { return false }
        guard appState.pickService.observedWeekId == weekId else { return false }
        return appState.pickService.didLoadSlateGames
            && appState.pickService.didLoadNominations
            && appState.pickService.didLoadVetoes
    }

    private func vetoCard(_ veto: SelectionVeto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(veto.matchupLabel)
                .font(.headline)
                .foregroundStyle(PickemsColors.textPrimary)
            Text("This Selection was vetoed. \(veto.voteCount) of \(veto.votesNeeded) votes removed it, and that member can pick a different game.")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private func gameCard(_ game: SlateGame) -> some View {
        let picked = appState.pickService.userPick?.picks[game.id]
            ?? appState.picksViewModel.draftPicks[game.id]
        return VStack(alignment: .leading, spacing: 12) {
            if let score = scoreLine(game) {
                Text(score)
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)
                    .padding(.horizontal)
            }
            GamePickRow(
                game: game,
                selectedTeamId: picked,
                isDisabled: true,
                liveCard: appState.picksViewModel.livePickCards[game.espnEventId],
                homeRank: appState.picksViewModel.teamRanks.rank(for: game.homeTeamId),
                awayRank: appState.picksViewModel.teamRanks.rank(for: game.awayTeamId),
                showsSpread: appState.selectedPickMode.showsSpreads,
                onSelect: { _ in }
            )
            .padding(.horizontal)
        }
    }

    private func scoreLine(_ game: SlateGame) -> String? {
        guard let away = game.awayScore, let home = game.homeScore else { return nil }
        let status = game.status == .final ? "Final" : "Score"
        return "\(status) \(game.awayTeamAbbreviation) \(away) @ \(game.homeTeamAbbreviation) \(home)"
    }
}
