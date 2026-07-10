import WidgetKit
import SwiftUI

struct PickemsWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandingsEntry {
        StandingsEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StandingsEntry) -> Void) {
        completion(StandingsEntry(date: Date(), snapshot: PickemsAppGroup.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StandingsEntry>) -> Void) {
        let entry = StandingsEntry(date: Date(), snapshot: PickemsAppGroup.load() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct StandingsEntry: TimelineEntry {
    let date: Date
    let snapshot: StandingsSnapshot
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

    var body: some View {
        switch family {
        case .systemSmall:
            small
        case .systemLarge, .systemExtraLarge:
            large
        default:
            medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot.groupName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("#\(entry.snapshot.rank)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("W\(entry.snapshot.weekNumber) · \(entry.snapshot.weeklyRecord)")
                .font(.caption.weight(.semibold))
            Text("Season \(entry.snapshot.seasonRecord)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color(red: 0.08, green: 0.08, blue: 0.10)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.snapshot.groupName)
                    .font(.caption.weight(.bold))
                Spacer()
                Text("Week \(entry.snapshot.weekNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.snapshot.topEntries.prefix(3)) { row in
                HStack {
                    Text("#\(row.rank) \(row.displayName)")
                        .font(.caption.weight(row.id == entry.snapshot.userId ? .bold : .regular))
                    Spacer()
                    Text("\(row.weeklyWins)-\(row.weeklyLosses)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(row.id == entry.snapshot.userId ? Color.red : Color.primary)
            }
        }
        .containerBackground(for: .widget) {
            Color(red: 0.08, green: 0.08, blue: 0.10)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(entry.snapshot.groupName) · Season")
                .font(.headline)
            ForEach(entry.snapshot.topEntries) { row in
                HStack {
                    Text("#\(row.rank)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 28, alignment: .leading)
                    Text(row.displayName)
                        .font(.subheadline.weight(row.id == entry.snapshot.userId ? .bold : .regular))
                    Spacer()
                    Text("\(row.seasonWins)-\(row.seasonLosses)")
                        .font(.subheadline.monospacedDigit())
                }
            }
            Spacer()
            Text("You: #\(entry.snapshot.rank) · \(entry.snapshot.seasonRecord)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) {
            Color(red: 0.08, green: 0.08, blue: 0.10)
        }
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}
