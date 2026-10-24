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

    @State private var showingInfo = false

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
                    infoButton(message: infoMessage)
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

    private func infoButton(message: String) -> some View {
        Button {
            PickemsHaptics.lightImpact()
            showingInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                // Compact glyph; expand the hit target to at least 44×44 without growing the row.
                .frame(width: 18, height: 18)
                .contentShape(Rectangle().inset(by: -13))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Line info")
        .accessibilityHint("Explains the locked and current line.")
        .popover(isPresented: $showingInfo, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textPrimary)
                .padding()
                .frame(maxWidth: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }
}
