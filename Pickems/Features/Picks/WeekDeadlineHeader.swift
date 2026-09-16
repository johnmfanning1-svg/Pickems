import SwiftUI

/// Prominent live countdown for this week’s Selection and Pickems deadlines.
struct WeekDeadlineHeader: View {
    let snapshot: WorkspaceDeadlineSnapshot
    @Environment(\.themePalette) private var theme

    var body: some View {
        if snapshot.hasContent {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                card(now: context.date)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
        }
    }

    private func card(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let deadline = snapshot.selectionDeadline {
                DeadlineHeroRow(
                    eyebrow: "Selections",
                    deadline: deadline,
                    openTitle: "Due \(PickDeadlineCalculator.lockTimeLabel(for: deadline))",
                    lockedTitle: "Selections locked",
                    help: PickemsHelp.selectionDeadline,
                    now: now
                )
            } else if snapshot.showSetSelectionDeadlinePrompt {
                setSelectionPrompt
            }

            if snapshot.selectionDeadline != nil || snapshot.showSetSelectionDeadlinePrompt,
               snapshot.pickemsDeadline != nil {
                Divider().overlay(Color.white.opacity(0.08))
            }

            if let deadline = snapshot.pickemsDeadline {
                DeadlineHeroRow(
                    eyebrow: snapshot.isRolling ? "Pickems · next lock" : "Pickems",
                    deadline: deadline,
                    openTitle: snapshot.isRolling
                        ? "Next lock \(PickDeadlineCalculator.lockTimeLabel(for: deadline))"
                        : "Lock \(PickDeadlineCalculator.lockTimeLabel(for: deadline))",
                    lockedTitle: "Pickems locked",
                    help: PickemsHelp.pickDeadline,
                    now: now,
                    rollingDetail: rollingDetail
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accentColor(now: now).opacity(0.28), lineWidth: 1)
        )
    }

    private var rollingDetail: String? {
        guard snapshot.isRolling, snapshot.totalCount > 0 else { return nil }
        return "\(snapshot.openCount) of \(snapshot.totalCount) games still open"
    }

    private var setSelectionPrompt: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.badge.questionmark")
                .font(.title2)
                .foregroundStyle(PickemsColors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Selections")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .textCase(.uppercase)
                Text("Set a Selection deadline")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Members need a due time so they finish before kickoff. Set it in Commissioner Settings.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HelpInfoButton(topic: PickemsHelp.selectionDeadline, size: .subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selections, set a Selection deadline in Commissioner Settings")
    }

    private func accentColor(now: Date) -> Color {
        let deadlines = [snapshot.selectionDeadline, snapshot.pickemsDeadline].compactMap { $0 }
        if deadlines.contains(where: { !PickDeadlineCalculator.isPast($0, now: now) }) {
            return PickemsColors.warning
        }
        return theme.accent
    }
}
