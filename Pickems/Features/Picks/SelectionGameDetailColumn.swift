import SwiftUI

/// Compact trailing column on a Selections card. Kickoff (or live/final) sits on top.
struct SelectionGameDetailColumn: View {
    let detail: SelectionGameDetail

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(detail.headline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(headlineColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let network = detail.network {
                Text(network)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if let records = detail.records {
                Text(records)
                    .font(.caption2)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
            }
        }
        .layoutPriority(1)
        .multilineTextAlignment(.trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.accessibilityLabel)
    }

    private var headlineColor: Color {
        switch detail.phase {
        case .live:
            PickemsColors.warning
        case .scheduled, .final:
            PickemsColors.textPrimary
        }
    }
}
