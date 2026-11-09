import SwiftUI

struct CoverMomentView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    let gameLabel: String
    let resultTitle: String
    let recordText: String
    let rankText: String
    let shareSource: ShareSource?

    @State private var appeared = false

    var body: some View {
        ZStack {
            PickemsAtmosphericBackground(palette: theme)
            VStack(spacing: 28) {
                Spacer()
                Text(resultTitle)
                    .font(PickemsTypography.display(40))
                    .foregroundStyle(theme.accent)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text(gameLabel)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(PickemsColors.textPrimary)
                Text(recordText)
                    .font(PickemsTypography.display(28).monospacedDigit())
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(rankText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(PickemsColors.textSecondary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                if let shareSource {
                    ShareResultsButton(source: shareSource)
                        .padding(.horizontal, 24)
                        .opacity(appeared ? 1 : 0)
                }

                Button("Keep watching") {
                    dismiss()
                }
                .font(.headline)
                .foregroundStyle(theme.accent)
                .padding(.top, 8)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                appeared = true
            }
            // Misses stay on the card. This sheet is a win or a cover.
            if resultTitle != "Missed" {
                PickemsHaptics.success()
            }
        }
    }
}

@MainActor
@Observable
final class CoverMomentPresenter {
    private var seenFinalGameIds = Set<String>()
    private var loadedKey: String?
    /// Set once the slate for `loadedKey` has actually arrived. An empty first
    /// snapshot must not count, or the load that follows would look like a live final.
    private var seededKey: String?
    private var defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `absorbCurrentlyFinal` is true on the observation that brings the app back to the foreground,
    /// so finals that landed while it was away are marked seen and do not open the sheet.
    func observe(appState: AppState, isForeground: Bool, absorbCurrentlyFinal: Bool) {
        guard let userId = appState.currentUserId,
              let groupId = appState.groupService.selectedGroup?.id,
              let weekId = appState.groupService.currentWeek?.id else { return }

        let key = CelebrationStore.seenFinalsKey(groupId: groupId, weekId: weekId)
        if loadedKey != key {
            loadedKey = key
            seededKey = nil
            seenFinalGameIds = CelebrationStore.loadSeenFinals(
                groupId: groupId,
                weekId: weekId,
                defaults: defaults
            )
        }
        let slate = appState.pickService.slateGames
        let isFirstObservation = seededKey != key

        let mode = appState.selectedPickMode
        let pick = appState.pickService.userPick
        let games = slate.map { game in
            observedGame(game, pick: pick, pickMode: mode)
        }
        let outcome = CelebrationPolicy.observe(
            games: games,
            previouslySeen: seenFinalGameIds,
            isFirstObservation: isFirstObservation,
            isForeground: isForeground,
            absorbCurrentlyFinal: absorbCurrentlyFinal,
            winTitle: mode.coverMomentWinTitle
        )
        seenFinalGameIds = outcome.seen
        CelebrationStore.saveSeenFinals(outcome.seen, groupId: groupId, weekId: weekId, defaults: defaults)
        if !slate.isEmpty {
            seededKey = key
        }

        guard !isFirstObservation, let gameId = outcome.sheetGameId,
              let game = appState.pickService.slateGames.first(where: { $0.id == gameId }) else { return }

        let label = "\(game.awayTeamAbbreviation) @ \(game.homeTeamAbbreviation)"
        let recordText: String
        let rankText: String
        if let entry = appState.rankedStandings(weekly: true).first(where: { $0.id == userId }) {
            recordText = CelebrationPolicy.recordLine(wins: entry.weeklyWins, losses: entry.weeklyLosses)
            let pulse = PulseRankCopy.display(
                entry: entry,
                board: appState.rankedStandings(weekly: true)
            )
            rankText = pulse.animatableRank == nil ? "" : "You're \(pulse.rankText) live"
        } else {
            recordText = "Pick settled"
            rankText = ""
        }
        appState.present(
            .coverMoment(
                gameLabel: label,
                resultTitle: mode.coverMomentWinTitle,
                recordText: recordText,
                rankText: rankText
            ),
            policy: .ifIdle
        )
    }

    private func observedGame(_ game: SlateGame, pick: UserPick?, pickMode: PickMode) -> CelebrationPolicy.ObservedGame {
        let picked = pick?.picks[game.id]
        let pickedId = (picked?.isEmpty == false) ? picked : nil
        let correct = pickedId.flatMap {
            ScoringEngine.isPickCorrect(pickedTeamId: $0, game: game, pickMode: pickMode)
        }
        let hasScores = game.homeScore != nil && game.awayScore != nil
        let isPush = game.status == .final && pickedId != nil && hasScores && correct == nil
        return CelebrationPolicy.ObservedGame(
            id: game.id,
            isFinal: game.status == .final,
            isCorrect: correct,
            isPush: isPush
        )
    }
}
