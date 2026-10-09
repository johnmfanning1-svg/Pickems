import SwiftUI

/// Prominent countdown for this week’s Selection and Pickems deadlines.
/// A locked or closed Selection row is static and does not tick.
struct WeekDeadlineHeader: View {
    let snapshot: WorkspaceDeadlineSnapshot
    /// Commissioner tap on a row that is prompting for a deadline. Nil keeps every row static.
    var onSetDeadline: ((WorkspaceDeadlineKind) -> Void)? = nil
    @Environment(\.themePalette) private var theme

    var body: some View {
        if snapshot.hasContent {
            card
                .padding(.horizontal)
                .accessibilityElement(children: .contain)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            selectionSection
            if showsDivider {
                Divider().overlay(Color.white.opacity(0.08))
            }
            pickemsSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(cardBorder)
    }

    @ViewBuilder
    private var selectionSection: some View {
        switch snapshot.selectionState {
        case .open(let deadline):
            TimelineView(.periodic(from: .now, by: 30)) { context in
                openSelectionRow(deadline: deadline, now: context.date)
            }
        case .locked(let copy):
            SelectionLockedRow(copy: copy)
        case .needsDeadline:
            if snapshot.showSetSelectionDeadlinePrompt {
                promptTapTarget(.selections) { setSelectionPrompt }
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var pickemsSection: some View {
        if let deadline = snapshot.pickemsDeadline {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                promptTapTarget(.pickems) {
                    pickemsRow(deadline: deadline, now: context.date)
                }
            }
        }
    }

    private var showsDivider: Bool {
        showsSelectionRow && snapshot.pickemsDeadline != nil
    }

    private var showsSelectionRow: Bool {
        switch snapshot.selectionState {
        case .open, .locked:
            return true
        case .needsDeadline:
            return snapshot.showSetSelectionDeadlinePrompt
        case nil:
            return false
        }
    }

    private func isTappable(_ kind: WorkspaceDeadlineKind) -> Bool {
        onSetDeadline != nil && snapshot.isPromptingCommissioner(for: kind)
    }

    /// Wraps a row in a button only while it prompts the commissioner.
    @ViewBuilder
    private func promptTapTarget<Content: View>(
        _ kind: WorkspaceDeadlineKind,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if isTappable(kind), let onSetDeadline {
            Button {
                PickemsHaptics.selection()
                onSetDeadline(kind)
            } label: {
                content()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(kind == .selections
                ? "Opens the Selection deadline editor."
                : "Opens the Pickems deadline editor.")
        } else {
            content()
        }
    }

    private func openSelectionRow(deadline: Date, now: Date) -> some View {
        DeadlineHeroRow(
            eyebrow: "Selections",
            deadline: deadline,
            openTitle: "Due \(PickDeadlineCalculator.lockTimeLabel(for: deadline))",
            lockedTitle: "Locked",
            help: PickemsHelp.selectionDeadline,
            now: now
        )
    }

    private func pickemsRow(deadline: Date, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if isTappable(.pickems) {
                Text("No Pickems deadline set yet. Tap to set one.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rollingDetail: String? {
        guard snapshot.isRolling, snapshot.totalCount > 0 else { return nil }
        return "\(snapshot.openCount) of \(snapshot.totalCount) games still open"
    }

    private var setSelectionPrompt: some View {
        SelectionDeadlinePrompt(tappable: isTappable(.selections))
    }

    @ViewBuilder
    private var cardBorder: some View {
        if snapshot.clockIsLive {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                borderStroke(now: context.date)
            }
        } else {
            borderStroke(now: Date())
        }
    }

    private func borderStroke(now: Date) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(accentColor(now: now).opacity(0.28), lineWidth: 1)
    }

    /// Warning only while something on the card is still counting down.
    private func accentColor(now: Date) -> Color {
        if case .open(let deadline) = snapshot.selectionState,
           !PickDeadlineCalculator.isPast(deadline, now: now) {
            return PickemsColors.warning
        }
        if let pickems = snapshot.pickemsDeadline,
           !PickDeadlineCalculator.isPast(pickems, now: now) {
            return PickemsColors.warning
        }
        return theme.accent
    }
}

/// Commissioner prompt to set a Selection deadline. Not shown once Selections are closed.
private struct SelectionDeadlinePrompt: View {
    let tappable: Bool

    var body: some View {
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
                Text(tappable
                    ? "Members need a due time so they finish before kickoff. Tap to set it."
                    : "Members need a due time so they finish before kickoff. Set it in Commissioner Settings.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if tappable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .accessibilityHidden(true)
            } else {
                HelpInfoButton(topic: PickemsHelp.selectionDeadline, size: .subheadline)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tappable
            ? "Selections, set a Selection deadline"
            : "Selections, set a Selection deadline in Commissioner Settings")
    }
}
