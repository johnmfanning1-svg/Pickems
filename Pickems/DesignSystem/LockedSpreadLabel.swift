import SwiftUI

/// Pickems line with an optional lock and live ESPN line in parentheses.
struct LockedSpreadLabel: View {
    let lockedText: String
    var liveText: String? = nil
    var isLocked: Bool = true
    var font: Font = .caption2.weight(.semibold)
    var lockedColor: Color = PickemsColors.textSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .accessibilityHidden(true)
            }
            Text(SpreadLineCopy.caption(locked: lockedText, live: liveText))
                .font(font)
                .foregroundStyle(lockedColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            SpreadLineCopy.accessibilityLabel(
                locked: lockedText,
                live: liveText,
                isLocked: isLocked
            )
        )
    }
}
