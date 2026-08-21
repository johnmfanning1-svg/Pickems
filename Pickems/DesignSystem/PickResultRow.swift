import SwiftUI

struct PickResultRow: View {
    let game: SlateGame
    let pickedTeamId: String?
    var showSpread: Bool = true
    var homeRank: Int? = nil
    var awayRank: Int? = nil
    @Environment(\.themePalette) private var theme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    TeamDisplay.matchupLabel(
                        awayAbbreviation: game.awayTeamAbbreviation,
                        awayRank: awayRank,
                        homeAbbreviation: game.homeTeamAbbreviation,
                        homeRank: homeRank,
                        separator: game.matchupSeparator
                    )
                )
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textPrimary)
                if showSpread {
                    Text(game.spreadLabel(for: game.spreadTeamId))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            Spacer()
            if let pickedTeamId {
                Text(pickedTeamId == game.homeTeamId ? game.homeTeamAbbreviation : game.awayTeamAbbreviation)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                if let result = ScoringEngine.isPickCorrect(pickedTeamId: pickedTeamId, game: game) {
                    Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result ? PickemsColors.success : theme.accent)
                        .accessibilityLabel(result ? "Win" : "Loss")
                }
            } else {
                Text("—")
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
    }
}
