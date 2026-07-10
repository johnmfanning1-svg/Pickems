import SwiftUI

struct PickDeadlineBanner: View {
    let deadline: Date
    let isPast: Bool
    @Environment(\.themePalette) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isPast ? "lock.fill" : "clock.fill")
                .font(.title3)
                .foregroundStyle(isPast ? theme.accent : PickemsColors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isPast ? "Pick deadline passed" : "Picks due")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(isPast
                    ? deadline.formatted(date: .abbreviated, time: .shortened)
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
