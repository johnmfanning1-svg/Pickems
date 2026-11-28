import SwiftUI

struct LeaderboardShareCard: View {
    let model: LeaderboardShareModel

    var body: some View {
        ShareCardChrome(
            leagueName: model.leagueName,
            periodLabel: model.periodLabel,
            contextTitle: "Leaderboard"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
                if model.omittedCount > 0 {
                    Text("+\(model.omittedCount) more")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func rowView(_ row: ShareLeaderboardRow) -> some View {
        HStack(spacing: 16) {
            Text("#\(row.rank)")
                .font(PickemsTypography.display(26).monospacedDigit())
                .foregroundStyle(PickemsColors.accent)
                .frame(width: 56, alignment: .leading)

            ShareStaticAvatar(
                initials: String(row.displayName.prefix(2)).uppercased(),
                colorHex: row.avatarColorHex,
                size: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(row.isViewer ? PickemsColors.accent : PickemsColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(row.caption)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            Text("\(row.wins)–\(row.losses)")
                .font(.system(size: 28, weight: .bold).monospacedDigit())
                .foregroundStyle(PickemsColors.textPrimary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(row.isViewer ? PickemsColors.cardBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}