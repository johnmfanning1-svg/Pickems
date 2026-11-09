import SwiftUI

/// League status at the top of Home. Used only by `HomeView`.
struct HomeLeagueStatusHeader<Footer: View>: View {
    let status: HomeLeagueStatus.Model
    /// Signed-in member. The status block opens their league profile. The footer stays a separate control.
    var profileUserId: String? = nil
    @ViewBuilder var footer: () -> Footer
    @Environment(\.themePalette) private var theme

    var body: some View {
        PickemsCard {
            VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
                if let profileUserId {
                    LeagueMemberProfileLink(userId: profileUserId, hint: "Opens your league profile") {
                        statusBlock
                    }
                } else {
                    statusBlock
                }

                footer()
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            Text(status.leagueName)
                .font(PickemsTypography.display(22))
                .foregroundStyle(PickemsColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: PickemsSpacing.xs) {
                Text(status.weekLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                if let stage = status.stage {
                    StatusBadge(text: stage.title, color: stageColor(stage))
                }
                Spacer(minLength: 0)
            }

            if let detail = status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }

            HStack(alignment: .top, spacing: 0) {
                statColumn(title: "This week", stat: status.week)
                Rectangle()
                    .fill(PickemsColors.hairline)
                    .frame(width: 1, height: 44)
                statColumn(title: "Season", stat: status.season)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }

    private func statColumn(title: String, stat: HomeLeagueStatus.Stat) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
            Text(stat.recordText)
                .font(stat.accessibilityRecord == nil
                    ? .title3.weight(.bold).monospacedDigit()
                    : .caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            rankText(stat)
        }
        .frame(maxWidth: .infinity)
    }

    private func rankText(_ stat: HomeLeagueStatus.Stat) -> some View {
        Text(stat.rankText)
            .font(.subheadline.weight(.bold).monospacedDigit())
            .foregroundStyle(stat.animatableRank == nil ? PickemsColors.textSecondary : theme.accent)
            .lineLimit(1)
            .homeLeagueRankMotion(stat.animatableRank)
    }

    private func stageColor(_ stage: HomeLeagueStatus.Stage) -> Color {
        switch stage {
        case .selections, .pickems:
            return theme.accent
        case .locked:
            return PickemsColors.textSecondary
        case .live:
            return PickemsColors.warning
        case .final:
            return PickemsColors.success
        }
    }
}

private extension View {
    @ViewBuilder
    func homeLeagueRankMotion(_ rank: Int?) -> some View {
        if let rank {
            self.pickemsRankMotion(trigger: rank)
        } else {
            self
        }
    }
}
