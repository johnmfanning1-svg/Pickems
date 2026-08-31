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
                        .font(PickemsTypography.display(28))
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text(rankText)
                        .font(.subheadline)
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
            PickemsHaptics.success()
        }
    }
}

@MainActor
@Observable
final class CoverMomentPresenter {
    private var seenFinalGameIds = Set<String>()

    func observe(appState: AppState) {
        guard let userId = appState.authService.currentUser?.id else { return }
        let games = appState.pickService.slateGames
        let pick = appState.pickService.userPick
        for game in games where game.status == .final {
            guard !seenFinalGameIds.contains(game.id) else { continue }
            seenFinalGameIds.insert(game.id)
            guard let picked = pick?.picks[game.id],
                  let correct = ScoringEngine.isPickCorrect(pickedTeamId: picked, game: game) else {
                continue
            }
            let label = "\(game.awayTeamAbbreviation) @ \(game.homeTeamAbbreviation)"
            let resultTitle = correct ? "Covered" : "Missed"
            let recordText: String
            let rankText: String
            if let entry = appState.rankedStandings(weekly: true).first(where: { $0.id == userId }) {
                recordText = "\(entry.weeklyWins)–\(entry.weeklyLosses) today"
                rankText = "You're #\(entry.rank) live"
            } else {
                recordText = "Pick settled"
                rankText = ""
            }
            appState.present(.coverMoment(
                gameLabel: label,
                resultTitle: resultTitle,
                recordText: recordText,
                rankText: rankText
            ))
            break
        }
    }
}
