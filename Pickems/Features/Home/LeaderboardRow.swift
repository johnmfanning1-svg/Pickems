import SwiftUI

struct LeaderboardRow: View {
    let entry: StandingEntry
    var showWeekly: Bool = false
    var streak: Int = 0
    var isPerfectSaturday: Bool = false
    var isCommissioner: Bool = false
    @Environment(\.themePalette) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(entry.rank)")
                .font(PickemsTypography.display(18))
                .foregroundStyle(theme.accent)
                .frame(width: 36, alignment: .leading)
                .accessibilityHidden(true)
                .pickemsRankMotion(trigger: entry.rank)

            InitialsAvatar(
                initials: String(entry.displayName.prefix(2)).uppercased(),
                colorHex: entry.avatarColorHex,
                imageURL: entry.avatarImageURL,
                size: 36
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PickemsColors.textPrimary)
                    if isCommissioner {
                        Image(systemName: "gavel")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .accessibilityLabel("Commissioner")
                    }
                }
                HStack(spacing: 6) {
                    if entry.isTied {
                        Text("Tied")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                    }
                    StreakBadgeView(streak: streak, isPerfect: isPerfectSaturday)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if showWeekly {
                    Text("\(entry.weeklyWins)-\(entry.weeklyLosses)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text(BattingAverage.formatted(wins: entry.weeklyWins, losses: entry.weeklyLosses))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(PickemsColors.textSecondary)
                } else {
                    Text("\(entry.seasonWins)-\(entry.seasonLosses)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text(BattingAverage.formatted(wins: entry.seasonWins, losses: entry.seasonLosses))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let record = showWeekly
            ? "\(entry.weeklyWins) wins, \(entry.weeklyLosses) losses this week"
            : "\(entry.seasonWins) wins, \(entry.seasonLosses) losses this season"
        let tied = entry.isTied ? ", tied for rank" : ""
        let role = isCommissioner ? ", commissioner" : ""
        return "Rank \(entry.rank), \(entry.displayName)\(role), \(record)\(tied)"
    }
}
