import SwiftUI

/// Locked Pickems line with a Locked pill, optional market-line caption, and info popover.
struct LockedSpreadLabel: View {
    let lockedText: String
    var liveText: String? = nil
    var isLocked: Bool = true
    /// When true, the second line uses "Closing line"; otherwise "Current line".
    var isFinal: Bool = false
    var font: Font = .caption2.weight(.semibold)
    var lockedColor: Color = PickemsColors.textSecondary

    private var referenceCaption: String? {
        guard isLocked else { return nil }
        return SpreadLineCopy.referenceCaption(locked: lockedText, live: liveText, isFinal: isFinal)
    }

    private var infoMessage: String? {
        guard isLocked, let liveText else { return nil }
        return SpreadLineCopy.infoMessage(locked: lockedText, live: liveText, isFinal: isFinal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                // Combined locked-line label; info button stays its own element so VoiceOver can open it.
                HStack(alignment: .center, spacing: 6) {
                    Text(lockedText)
                        .font(font)
                        .foregroundStyle(lockedColor)

                    if isLocked {
                        lockedPill
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    SpreadLineCopy.accessibilityLabel(
                        locked: lockedText,
                        live: liveText,
                        isLocked: isLocked,
                        isFinal: isFinal
                    )
                )

                if let infoMessage {
                    SpreadLineInfoButton(message: infoMessage, isFinal: isFinal)
                }
            }

            if let referenceCaption {
                Text(referenceCaption)
                    .font(.caption2)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var lockedPill: some View {
        Text("Locked")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(PickemsColors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(PickemsColors.textSecondary.opacity(0.55), lineWidth: 1)
            )
    }

}

/// ⓘ that presents the locked-vs-market line popover, anchored to this control.
struct SpreadLineInfoButton: View {
    let message: String
    var isFinal: Bool
    var font: Font = .caption.weight(.semibold)
    /// Comfortable expands a small glyph to a 44pt hit target. Dense already lives in a 48pt row,
    /// so it keeps the target inside that row.
    var containsHitTarget: Bool = false

    @State private var infoTrigger = AnchoredInfoPopoverTrigger()
    @AccessibilityFocusState private var infoButtonFocused: Bool

    var body: some View {
        Button {
            PickemsHaptics.lightImpact()
            infoTrigger.fire()
        } label: {
            Image(systemName: "info.circle")
                .font(font)
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(width: containsHitTarget ? 32 : 18, height: containsHitTarget ? 44 : 18)
                .contentShape(Rectangle().inset(by: containsHitTarget ? 0 : -13))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Line info")
        .accessibilityHint(SpreadLineCopy.infoAccessibilityHint(isFinal: isFinal))
        .accessibilityFocused($infoButtonFocused)
        .background {
            AnchoredInfoPopoverAnchor(
                message: message,
                trigger: infoTrigger,
                onDismissed: {
                    // Anchor view is accessibility-hidden; move VO back to this button.
                    infoButtonFocused = true
                }
            )
            .allowsHitTesting(false)
        }
    }
}
