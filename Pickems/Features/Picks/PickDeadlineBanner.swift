import SwiftUI

/// Prominently shows when Pickems lock. Pass the absolute `deadline` (typically
/// `week.pickDeadline` or the next rolling kickoff); past/open is derived via
/// `PickDeadlineCalculator.isPast`.
struct PickDeadlineBanner: View {
    let deadline: Date
    var isRolling: Bool = false
    var openCount: Int = 0
    var totalCount: Int = 0

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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            DeadlineHeroCard(
                eyebrow: isRolling ? "Pickems · next lock" : "Pickems",
                deadline: deadline,
                openTitle: isRolling
                    ? "Next lock \(PickDeadlineCalculator.lockTimeLabel(for: deadline))"
                    : "Lock \(PickDeadlineCalculator.lockTimeLabel(for: deadline))",
                lockedTitle: "Pickems locked",
                help: PickemsHelp.pickDeadline,
                now: context.date,
                rollingDetail: rollingDetail
            )
        }
        .padding(.horizontal)
    }

    private var rollingDetail: String? {
        guard isRolling, totalCount > 0 else { return nil }
        return "\(openCount) of \(totalCount) games still open"
    }
}

/// Same visual language as `PickDeadlineBanner`, for the Selection deadline.
struct SelectionDeadlineBanner: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            DeadlineHeroCard(
                eyebrow: "Selections",
                deadline: deadline,
                openTitle: "Due \(PickDeadlineCalculator.lockTimeLabel(for: deadline))",
                lockedTitle: "Selections locked",
                help: PickemsHelp.selectionDeadline,
                now: context.date
            )
        }
        .padding(.horizontal)
    }
}

/// Large ticking countdown card used by standalone banners.
struct DeadlineHeroCard: View {
    let eyebrow: String
    let deadline: Date
    let openTitle: String
    let lockedTitle: String
    let help: HelpTopic
    var now: Date
    var rollingDetail: String? = nil
    @Environment(\.themePalette) private var theme

    private var isPast: Bool {
        PickDeadlineCalculator.isPast(deadline, now: now)
    }

    var body: some View {
        DeadlineHeroRow(
            eyebrow: eyebrow,
            deadline: deadline,
            openTitle: openTitle,
            lockedTitle: lockedTitle,
            help: help,
            now: now,
            rollingDetail: rollingDetail
        )
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    (isPast ? theme.accent : PickemsColors.warning).opacity(0.28),
                    lineWidth: 1
                )
        )
    }
}

/// Shared hero countdown row (no card chrome) for the dual week header.
struct DeadlineHeroRow: View {
    let eyebrow: String
    let deadline: Date
    let openTitle: String
    let lockedTitle: String
    let help: HelpTopic
    var now: Date
    var rollingDetail: String? = nil
    @Environment(\.themePalette) private var theme

    private var isPast: Bool {
        PickDeadlineCalculator.isPast(deadline, now: now)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isPast ? "lock.fill" : "clock.fill")
                .font(.title2)
                .foregroundStyle(isPast ? theme.accent : PickemsColors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .textCase(.uppercase)

                Text(isPast ? lockedTitle : PickDeadlineCalculator.countdownLabel(to: deadline, now: now))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PickemsColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(isPast ? PickDeadlineCalculator.lockTimeLabel(for: deadline) : openTitle)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let rollingDetail, !isPast {
                    Text(rollingDetail)
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }

            Spacer(minLength: 0)

            HelpInfoButton(topic: help, size: .subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isPast {
            return "\(eyebrow), \(lockedTitle), \(PickDeadlineCalculator.lockTimeLabel(for: deadline))"
        }
        var label = "\(eyebrow), \(PickDeadlineCalculator.countdownLabel(to: deadline, now: now)), \(openTitle)"
        if let rollingDetail {
            label += ", \(rollingDetail)"
        }
        return label
    }
}
