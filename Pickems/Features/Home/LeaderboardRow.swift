import SwiftUI

struct LeaderboardRow: View {
    let entry: StandingEntry
    var showWeekly: Bool = false
    var streak: Int = 0
    var isPerfectSaturday: Bool = false
    var isCommissioner: Bool = false
    var showsDisclosure: Bool = false
    /// Keep the chevron's width even when the chevron is hidden so records line up with tappable rows.
    var reservesDisclosureSpace: Bool = false
    /// When set, ranks after first place show games back of this win total instead of batting average.
    var leaderWins: Int? = nil
    @Environment(\.themePalette) private var theme

    private var recordWins: Int { showWeekly ? entry.weeklyWins : entry.seasonWins }
    private var recordLosses: Int { showWeekly ? entry.weeklyLosses : entry.seasonLosses }

    private var secondaryCaption: String {
        StandingsGap.leaderboardCaption(
            rank: entry.rank,
            wins: recordWins,
            losses: recordLosses,
            leaderWins: leaderWins
        )
    }

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
                Text("\(recordWins)-\(recordLosses)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(secondaryCaption)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(PickemsColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if showsDisclosure || reservesDisclosureSpace {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .opacity(showsDisclosure ? 1 : 0)
                    .accessibilityHidden(true)
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
        let secondary: String
        if entry.rank <= 1 || leaderWins == nil {
            secondary = "batting average \(secondaryCaption)"
        } else {
            let back = (leaderWins ?? recordWins) - recordWins
            secondary = back == 0 ? "Even" : "\(back) games back"
        }
        return "Rank \(entry.rank), \(entry.displayName)\(role), \(record), \(secondary)\(tied)"
    }
}
