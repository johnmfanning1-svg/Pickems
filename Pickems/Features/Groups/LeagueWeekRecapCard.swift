import SwiftUI

struct LeagueWeekRecapCard: View {
    let recap: LeagueWeekRecap
    @Environment(\.themePalette) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("League Recap", systemImage: "text.quote")
                .font(.headline)
                .foregroundStyle(theme.accent)

            Text(recap.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)

            if let winnerLine = recap.winnerLine {
                Text(winnerLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let lastPlaceLine = recap.lastPlaceLine {
                Text(lastPlaceLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.lost)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let highlightLine = recap.highlightLine {
                Text(highlightLine)
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recap.shareText)
    }
}
