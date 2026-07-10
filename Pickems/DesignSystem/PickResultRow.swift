import SwiftUI

struct PickResultRow: View {
    let game: SlateGame
    let pickedTeamId: String?
    @Environment(\.themePalette) private var theme

    var body: some View {
        HStack {
            Text("\(game.awayTeamAbbreviation) @ \(game.homeTeamAbbreviation)")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textPrimary)
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
