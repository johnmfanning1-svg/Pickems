import SwiftUI

/// Prominently shows when picks lock. Pass the absolute `deadline` (typically
/// `week.pickDeadline`); past/open is derived via `PickDeadlineCalculator.isPast`.
///
/// - Open: title “Picks lock at Sat 12:00 PM”, subtitle countdown
/// - Past: title “Picks locked”, subtitle absolute lock time
struct PickDeadlineBanner: View {
    let deadline: Date
    @Environment(\.themePalette) private var theme

    init(deadline: Date) {
        self.deadline = deadline
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isPast ? "lock.fill" : "clock.fill")
                .font(.title3)
                .foregroundStyle(isPast ? theme.accent : PickemsColors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isPast ? "Picks locked" : "Picks lock at \(lockTime)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(isPast
                    ? lockTime
                    : PickDeadlineCalculator.countdownLabel(to: deadline))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PickemsColors.textSecondary)
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
