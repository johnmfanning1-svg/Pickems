import WidgetKit
import SwiftUI

struct PickemsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandingsEntry {
        StandingsEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StandingsEntry) -> Void) {
        if context.isPreview {
            completion(StandingsEntry(date: Date(), snapshot: .placeholder))
            return
        }
        completion(StandingsEntry(date: Date(), snapshot: PickemsAppGroup.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StandingsEntry>) -> Void) {
        let entry = StandingsEntry(date: Date(), snapshot: PickemsAppGroup.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct StandingsEntry: TimelineEntry {
    let date: Date
    /// `nil` when App Group has no published snapshot (real empty state — not demo data).
    let snapshot: StandingsSnapshot?
}

extension StandingsSnapshot {
    static let placeholder = StandingsSnapshot(
        groupId: "demo",
        groupName: "Saturday Crew",
        weekNumber: 7,
        seasonYear: 2026,
        userId: "u1",
        userDisplayName: "You",
        weeklyWins: 4,
        weeklyLosses: 2,
        seasonWins: 28,
        seasonLosses: 14,
        rank: 2,
        totalPlayers: 8,
        topEntries: [
            .init(id: "1", displayName: "Alex", weeklyWins: 5, weeklyLosses: 1, seasonWins: 30, seasonLosses: 12, rank: 1),
            .init(id: "u1", displayName: "You", weeklyWins: 4, weeklyLosses: 2, seasonWins: 28, seasonLosses: 14, rank: 2),
            .init(id: "3", displayName: "Sam", weeklyWins: 3, weeklyLosses: 3, seasonWins: 25, seasonLosses: 17, rank: 3),
        ],
        updatedAt: Date()
    )
}

struct PickemsWidgetEntryView: View {
    var entry: StandingsEntry
    @Environment(\.widgetFamily) private var family
    @ScaledMetric(relativeTo: .largeTitle) private var rankPointSize: CGFloat = 36

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(for: snapshot)
            } else {
                emptyState
            }
        }
        // Near-black containerBackground: force dark scheme so primary/secondary text stays light in Light Mode.
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(for snapshot: StandingsSnapshot) -> some View {
        switch family {
        case .systemSmall:
            small(snapshot)
        case .systemLarge, .systemExtraLarge:
            large(snapshot)
        case .accessoryRectangular:
            accessoryRectangular(snapshot)
        case .accessoryCircular:
            accessoryCircular(snapshot)
        default:
            medium(snapshot)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pickems")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            Text("Open Pickems")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("to see standings")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pickems. Open Pickems to see standings.")
    }

    private func small(_ snapshot: StandingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.groupName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("#\(snapshot.rank)")
                .font(.system(size: rankPointSize, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("W\(snapshot.weekNumber) · \(snapshot.weeklyRecord)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Season \(snapshot.seasonRecord)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    private func medium(_ snapshot: StandingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.groupName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Week \(snapshot.weekNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.topEntries.prefix(3)) { row in
                let isYou = row.id == snapshot.userId
                HStack {
                    Text("#\(row.rank) \(row.displayName)")
                        .font(.caption.weight(isYou ? .bold : .regular))
                    Spacer()
                    Text("\(row.weeklyWins)-\(row.weeklyLosses)")
                        .font(.caption.monospacedDigit().weight(isYou ? .bold : .regular))
                }
                .foregroundStyle(isYou ? Color.red : Color.primary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowAccessibilityLabel(row, isYou: isYou, weekly: true))
                .accessibilityAddTraits(isYou ? [.isSelected] : [])
            }
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    private func large(_ snapshot: StandingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(snapshot.groupName) · Season")
                .font(.headline)
                .foregroundStyle(.primary)
            ForEach(snapshot.topEntries) { row in
                let isYou = row.id == snapshot.userId
                HStack {
                    Text("#\(row.rank)")
                        .font(.caption.monospacedDigit().weight(isYou ? .bold : .regular))
                        .frame(width: 28, alignment: .leading)
                    Text(row.displayName)
                        .font(.subheadline.weight(isYou ? .bold : .regular))
                    Spacer()
                    Text("\(row.seasonWins)-\(row.seasonLosses)")
                        .font(.subheadline.monospacedDigit().weight(isYou ? .bold : .regular))
                }
                .foregroundStyle(isYou ? Color.red : Color.primary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowAccessibilityLabel(row, isYou: isYou, weekly: false))
                .accessibilityAddTraits(isYou ? [.isSelected] : [])
            }
            Spacer()
            Text("You: #\(snapshot.rank) · \(snapshot.seasonRecord)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    /// Compact Lock Screen / Dynamic Island rectangular glance.
    private func accessoryRectangular(_ snapshot: StandingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.groupName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text("#\(snapshot.rank) · \(snapshot.weeklyRecord)")
                .font(.headline.weight(.bold))
                .lineLimit(1)
            Text("Week \(snapshot.weekNumber)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    /// Compact Lock Screen circular glance — rank + weekly record.
    private func accessoryCircular(_ snapshot: StandingsSnapshot) -> some View {
        VStack(spacing: 0) {
            Text("#\(snapshot.rank)")
                .font(.headline.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(snapshot.weeklyRecord)
                .font(.caption2.monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    private var widgetBackground: Color {
        Color(red: 0.08, green: 0.08, blue: 0.10)
    }

    private func standingsAccessibilityLabel(_ snapshot: StandingsSnapshot) -> String {
        let wins = snapshot.weeklyWins
        let losses = snapshot.weeklyLosses
        let winWord = wins == 1 ? "win" : "wins"
        let lossWord = losses == 1 ? "loss" : "losses"
        return "Rank \(snapshot.rank), \(wins) \(winWord), \(losses) \(lossWord), \(snapshot.groupName)"
    }

    private func rowAccessibilityLabel(
        _ row: StandingsSnapshot.SnapshotEntry,
        isYou: Bool,
        weekly: Bool
    ) -> String {
        let wins = weekly ? row.weeklyWins : row.seasonWins
        let losses = weekly ? row.weeklyLosses : row.seasonLosses
        let youPrefix = isYou ? "You, " : ""
        return "\(youPrefix)rank \(row.rank), \(row.displayName), \(wins) to \(losses)"
    }
}

@main
struct PickemsWidgets: WidgetBundle {
    var body: some Widget {
        PickemsStandingsWidget()
        if #available(iOS 16.2, *) {
            PickemsLiveActivityWidget()
        }
    }
}

struct PickemsStandingsWidget: Widget {
    let kind = "PickemsStandingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PickemsWidgetProvider()) { entry in
            PickemsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pickems Standings")
        .description("Weekly and season group scores at a glance.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}
