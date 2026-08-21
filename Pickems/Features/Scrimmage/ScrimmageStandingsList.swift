import SwiftUI

/// Leaderboard for the scrimmage week. Mirrors `LeaderboardRow` styling
/// without requiring a `StandingEntry` / Firestore-backed model.
struct ScrimmageStandingsList: View {
    let standings: [ScrimmageStanding]

    private static let avatarHexes = [
        "#DB2626", "#3373D9", "#26A673", "#D98C1A", "#8C4DBF", "#4DB3CC",
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(standings.enumerated()), id: \.element.id) { index, entry in
                ScrimmageStandingRow(
                    entry: entry,
                    avatarColorHex: Self.avatarHexes[index % Self.avatarHexes.count],
                    isHighlighted: entry.isUser
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ScrimmageStandingRow: View {
    let entry: ScrimmageStanding
    let avatarColorHex: String
    let isHighlighted: Bool
    @Environment(\.themePalette) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(entry.rank)")
                .font(PickemsTypography.display(18))
                .foregroundStyle(isHighlighted ? theme.accent : PickemsColors.textSecondary)
                .frame(width: 36, alignment: .leading)
                .accessibilityHidden(true)

            InitialsAvatar(
                initials: String(entry.displayName.prefix(2)).uppercased(),
                colorHex: avatarColorHex,
                size: 36
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.subheadline.weight(isHighlighted ? .semibold : .medium))
                        .foregroundStyle(PickemsColors.textPrimary)
                    if entry.isUser {
                        StatusBadge(text: "You", color: theme.accent)
                    }
                }
            }

            Spacer()

            Text("\(entry.wins)-\(entry.losses)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(PickemsColors.textPrimary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHighlighted ? theme.accent.opacity(0.18) : PickemsColors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isHighlighted ? theme.accent.opacity(0.45) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let you = entry.isUser ? ", you" : ""
        return "Rank \(entry.rank), \(entry.displayName)\(you), \(entry.wins) wins, \(entry.losses) losses"
    }
}
