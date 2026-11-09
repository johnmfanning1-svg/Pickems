import ActivityKit
import SwiftUI
import WidgetKit

struct PickemsLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickemsLiveAttributes.self) { context in
            LiveActivityLockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.recordText)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.rankText ?? "W\(context.attributes.weekNumber)")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.groupName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityPickList(picks: Array(context.state.picks.prefix(2)), prominent: false)
                        .widgetURL(LiveActivityWidgetLink.url(
                            groupId: context.attributes.groupId,
                            weekId: context.attributes.weekId,
                            picks: context.state.picks
                        ))
                }
            } compactLeading: {
                Text(context.state.recordText)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } compactTrailing: {
                Text(LiveActivityIsland.compactTrailing(context))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } minimal: {
                Text(context.state.recordText)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

private struct LiveActivityLockScreen: View {
    let context: ActivityViewContext<PickemsLiveAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.groupName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("W\(context.attributes.weekNumber)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.recordText)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                    if let rank = context.state.rankText {
                        Text(rank)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
            }
            LiveActivityPickList(picks: context.state.picks, prominent: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(red: 0.07, green: 0.08, blue: 0.10))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(LiveActivityWidgetLink.url(
            groupId: context.attributes.groupId,
            weekId: context.attributes.weekId,
            picks: context.state.picks
        ))
        .accessibilityElement(children: .combine)
    }
}

private struct LiveActivityPickList: View {
    let picks: [LiveActivityPick]
    let prominent: Bool

    var body: some View {
        if picks.isEmpty {
            Text("No picks this week")
                .font(prominent ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.8))
        } else {
            VStack(alignment: .leading, spacing: prominent ? 6 : 4) {
                ForEach(picks, id: \.gameId) { pick in
                    LiveActivityPickRow(pick: pick, prominent: prominent)
                }
            }
        }
    }
}

private struct LiveActivityPickRow: View {
    let pick: LiveActivityPick
    let prominent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            scoreText
                .font(prominent ? .subheadline.monospacedDigit() : .caption.monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(trailing)
                .font(prominent ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var scoreText: Text {
        if let left = pick.pickedScore, let right = pick.opponentScore {
            return Text(pick.picked).fontWeight(.bold)
                + Text(" \(left)  \(pick.opponent) \(right)")
        }
        return Text(pick.picked).fontWeight(.bold) + Text(" vs \(pick.opponent)")
    }

    private var trailing: String {
        if pick.phase == "upcoming" {
            return Date(timeIntervalSince1970: pick.kickoffUnix).formatted(date: .omitted, time: .shortened)
        }
        return pick.resultLabel
    }

    private var statusColor: Color {
        switch pick.result {
        case "covering", "won":
            return Color(red: 0.45, green: 0.92, blue: 0.55)
        case "trailing", "lost":
            return Color(red: 1.0, green: 0.55, blue: 0.48)
        default:
            return Color.white.opacity(0.75)
        }
    }

    private var accessibilityText: String {
        if let left = pick.pickedScore, let right = pick.opponentScore {
            return "\(pick.picked) \(left), \(pick.opponent) \(right), \(pick.resultLabel)"
        }
        return "\(pick.picked) versus \(pick.opponent), \(trailing)"
    }
}

private enum LiveActivityIsland {
    static func compactTrailing(_ context: ActivityViewContext<PickemsLiveAttributes>) -> String {
        if let live = context.state.picks.first(where: { $0.phase == "live" }),
           let left = live.pickedScore, let right = live.opponentScore {
            return "\(left)-\(right)"
        }
        if let rank = context.state.rankText {
            return rank
        }
        return "W\(context.attributes.weekNumber)"
    }
}
