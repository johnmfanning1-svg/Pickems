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
        completion(StandingsEntry(date: Date(), snapshot: resolveSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StandingsEntry>) -> Void) {
        let snapshot = resolveSnapshot()
        let now = Date()

        if let snapshot, snapshot.showsPreseasonCountdown, let kickoff = snapshot.seasonKickoffAt {
            // Refresh the countdown about once an hour until kickoff.
            var entries: [StandingsEntry] = []
            for hour in 0..<24 {
                guard let date = Calendar.current.date(byAdding: .hour, value: hour, to: now),
                      date < kickoff else { break }
                entries.append(StandingsEntry(date: date, snapshot: snapshot))
            }
            if entries.isEmpty {
                entries = [StandingsEntry(date: now, snapshot: snapshot)]
            }
            let refresh = min(kickoff, entries.last?.date.addingTimeInterval(60 * 60) ?? now.addingTimeInterval(60 * 60))
            completion(Timeline(entries: entries, policy: .after(refresh)))
            return
        }

        let entry = StandingsEntry(date: now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
    }

    /// Prefer App Group data; synthesize a kickoff countdown in preseason even before the app publishes.
    private func resolveSnapshot() -> StandingsSnapshot? {
        if CFBSeasonCalendar.isPreseason() {
            let kickoff = CFBSeasonCalendar.nextSeasonKickoff()
            if let loaded = PickemsAppGroup.load() {
                var copy = loaded
                copy.seasonKickoffAt = kickoff
                // ESPN regular season starts at Week 1 — never surface Week 0.
                copy.weekNumber = max(1, copy.weekNumber)
                copy.seasonYear = CFBSeasonCalendar.seasonYear(containing: kickoff)
                return copy
            }
            return .preseasonCountdown(until: kickoff)
        }

        guard var loaded = PickemsAppGroup.load() else { return nil }
        // Stale preseason payload after kickoff — don't keep showing the countdown.
        if loaded.seasonKickoffAt != nil {
            loaded.seasonKickoffAt = nil
        }
        return loaded
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
        updatedAt: Date(),
        seasonKickoffAt: nil
    )

    static func preseasonCountdown(until kickoff: Date) -> StandingsSnapshot {
        StandingsSnapshot(
            groupId: "",
            groupName: "Pickems",
            weekNumber: 1,
            seasonYear: CFBSeasonCalendar.seasonYear(containing: kickoff),
            userId: "",
            userDisplayName: "You",
            weeklyWins: 0,
            weeklyLosses: 0,
            seasonWins: 0,
            seasonLosses: 0,
            rank: 0,
            totalPlayers: 0,
            topEntries: [],
            updatedAt: Date(),
            seasonKickoffAt: kickoff
        )
    }
}

struct PickemsWidgetEntryView: View {
    var entry: StandingsEntry
    @Environment(\.widgetFamily) private var family
    @ScaledMetric(relativeTo: .largeTitle) private var rankPointSize: CGFloat = 36

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if snapshot.showsPreseasonCountdown, let kickoff = snapshot.seasonKickoffAt {
                    preseasonContent(snapshot: snapshot, kickoff: kickoff, asOf: entry.date)
                } else {
                    content(for: snapshot)
                }
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

    @ViewBuilder
    private func preseasonContent(snapshot: StandingsSnapshot, kickoff: Date, asOf date: Date) -> some View {
        switch family {
        case .systemSmall:
            preseasonSmall(snapshot: snapshot, kickoff: kickoff, asOf: date)
        case .accessoryCircular:
            preseasonCircular(kickoff: kickoff, asOf: date)
        case .accessoryRectangular:
            preseasonRectangular(snapshot: snapshot, kickoff: kickoff, asOf: date)
        default:
            preseasonMedium(snapshot: snapshot, kickoff: kickoff, asOf: date)
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

    // MARK: - Preseason countdown

    private func preseasonSmall(snapshot: StandingsSnapshot, kickoff: Date, asOf date: Date) -> some View {
        let summary = CFBSeasonCalendar.countdownSummary(to: kickoff, from: date)
        return VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.groupName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(summary)
                .font(.system(size: rankPointSize, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("Until Kickoff")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(kickoff.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preseasonAccessibilityLabel(snapshot: snapshot, kickoff: kickoff, asOf: date))
    }

    private func preseasonMedium(snapshot: StandingsSnapshot, kickoff: Date, asOf date: Date) -> some View {
        let parts = CFBSeasonCalendar.countdown(to: kickoff, from: date)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.groupName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Kickoff")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("College football is almost here")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            HStack(spacing: 14) {
                countdownBlock(value: parts.days, label: "Days")
                countdownBlock(value: parts.hours, label: "Hours")
                countdownBlock(value: parts.minutes, label: "Min")
            }
            Text("Starts \(kickoff.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preseasonAccessibilityLabel(snapshot: snapshot, kickoff: kickoff, asOf: date))
    }

    private func countdownBlock(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func preseasonRectangular(snapshot: StandingsSnapshot, kickoff: Date, asOf date: Date) -> some View {
        let summary = CFBSeasonCalendar.countdownSummary(to: kickoff, from: date)
        return VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.groupName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(summary)
                .font(.headline.weight(.bold))
                .lineLimit(1)
            Text("Until Kickoff")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preseasonAccessibilityLabel(snapshot: snapshot, kickoff: kickoff, asOf: date))
    }

    private func preseasonCircular(kickoff: Date, asOf date: Date) -> some View {
        let summary = CFBSeasonCalendar.countdownSummary(to: kickoff, from: date)
        return VStack(spacing: 0) {
            Text(summary)
                .font(.caption.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("KO")
                .font(.caption2)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary) until college football kickoff")
    }

    // MARK: - In-season standings

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
            Text("\(snapshot.groupName) · Week \(snapshot.weekNumber)")
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
                    Text("\(row.weeklyWins)-\(row.weeklyLosses)")
                        .font(.subheadline.monospacedDigit().weight(isYou ? .bold : .regular))
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(row.seasonWins)-\(row.seasonLosses)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(isYou ? Color.red : Color.primary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowAccessibilityLabel(row, isYou: isYou, weekly: true))
                .accessibilityAddTraits(isYou ? [.isSelected] : [])
            }
            Spacer()
            Text("You: #\(snapshot.rank) · \(snapshot.weeklyRecord) this week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

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
        return "Week \(snapshot.weekNumber) standings. Rank \(snapshot.rank), \(wins) \(winWord), \(losses) \(lossWord), \(snapshot.groupName)"
    }

    private func preseasonAccessibilityLabel(snapshot: StandingsSnapshot, kickoff: Date, asOf date: Date) -> String {
        let summary = CFBSeasonCalendar.countdownSummary(to: kickoff, from: date)
        let day = kickoff.formatted(.dateTime.month(.wide).day())
        return "\(snapshot.groupName). \(summary) until college football kickoff on \(day)."
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
        .description("Kickoff countdown now; live group standings once the season starts.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}
