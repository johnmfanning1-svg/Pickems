import ActivityKit
import SwiftUI
import WidgetKit

struct PickemsLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickemsLiveAttributes.self) { context in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.groupName)
                        .font(.caption2.weight(.semibold))
                    Text("W\(context.attributes.weekNumber) · \(context.state.weeklyWins)-\(context.state.weeklyLosses)")
                        .font(.headline.monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("#\(context.state.rank)")
                        .font(.title2.bold().monospacedDigit())
                    Text(context.state.nextGameLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("#\(context.state.rank)")
                        .font(.title.bold())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.weeklyWins)-\(context.state.weeklyLosses)")
                        .font(.title3.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.nextGameLabel)
                        .font(.caption)
                }
            } compactLeading: {
                Text("#\(context.state.rank)")
                    .font(.caption.bold())
            } compactTrailing: {
                Text("\(context.state.weeklyWins)-\(context.state.weeklyLosses)")
                    .font(.caption.monospacedDigit())
            } minimal: {
                Text("#\(context.state.rank)")
                    .font(.caption2.bold())
            }
        }
    }
}
