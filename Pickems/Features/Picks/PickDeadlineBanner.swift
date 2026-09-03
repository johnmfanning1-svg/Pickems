import SwiftUI

/// Prominently shows when Pickems lock. Pass the absolute `deadline` (typically
/// `week.pickDeadline` or the next rolling kickoff); past/open is derived via
/// `PickDeadlineCalculator.isPast`.
struct PickDeadlineBanner: View {
    let deadline: Date
    var isRolling: Bool = false
    var openCount: Int = 0
    var totalCount: Int = 0
    @Environment(\.themePalette) private var theme

    init(deadline: Date, isRolling: Bool = false, openCount: Int = 0, totalCount: Int = 0) {
        self.deadline = deadline
        self.isRolling = isRolling
        self.openCount = openCount
        self.totalCount = totalCount
    }

    /// Compatibility for call sites still passing `isPast`. Value is ignored —
    /// open/past is always derived from `deadline` via `PickDeadlineCalculator.isPast`.
    init(deadline: Date, isPast: Bool) {
        self.deadline = deadline
        _ = isPast
    }

    private var isPast: Bool {
        PickDeadlineCalculator.isPast(deadline)
    }

    private var lockTime: String {
        PickDeadlineCalculator.lockTimeLabel(for: deadline)
    }

    private var title: String {
        if isPast { return "Pickems locked" }
        if isRolling { return "Next lock at \(lockTime)" }
        return "Pickems lock at \(lockTime)"
    }

    private var subtitle: String {
        if isPast { return lockTime }
        return PickDeadlineCalculator.countdownLabel(to: deadline)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isPast ? "lock.fill" : "clock.fill")
                .font(.title3)
                .foregroundStyle(isPast ? theme.accent : PickemsColors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(subtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PickemsColors.textSecondary)
                if isRolling, !isPast, totalCount > 0 {
                    Text("\(openCount) of \(totalCount) games still open")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }

            Spacer(minLength: 0)

            HelpInfoButton(topic: PickemsHelp.pickDeadline, size: .subheadline)
        }
        .padding()
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    (isPast ? theme.accent : PickemsColors.warning).opacity(0.2),
                    lineWidth: 1
                )
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

/// Same visual language as `PickDeadlineBanner`, for the Selection deadline.
struct SelectionDeadlineBanner: View {
    let deadline: Date
    @Environment(\.themePalette) private var theme

    private var isPast: Bool {
        PickDeadlineCalculator.isPast(deadline)
    }

    private var lockTime: String {
        PickDeadlineCalculator.lockTimeLabel(for: deadline)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isPast ? "lock.fill" : "clock.fill")
                .font(.title3)
                .foregroundStyle(isPast ? theme.accent : PickemsColors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isPast ? "Selections locked" : "Selections due \(lockTime)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(isPast
                    ? lockTime
                    : PickDeadlineCalculator.countdownLabel(to: deadline))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PickemsColors.textSecondary)
            }

            Spacer(minLength: 0)

            HelpInfoButton(topic: PickemsHelp.selectionDeadline, size: .subheadline)
        }
        .padding()
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    (isPast ? theme.accent : PickemsColors.warning).opacity(0.2),
                    lineWidth: 1
                )
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}
