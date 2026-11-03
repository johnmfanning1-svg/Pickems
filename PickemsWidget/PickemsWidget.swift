import WidgetKit
import SwiftUI
import AppIntents

struct PickemsWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StandingsEntry {
        StandingsEntry(date: Date(), snapshot: .placeholder, redacted: true)
    }

    func snapshot(for configuration: SelectLeagueIntent, in context: Context) async -> StandingsEntry {
        if context.isPreview {
            return StandingsEntry(date: Date(), snapshot: .gallerySample(for: context.family))
        }
        let resolved = resolveSnapshot(for: configuration)
        return StandingsEntry(
            date: Date(),
            snapshot: resolved.snapshot,
            pendingLeagueName: resolved.pendingLeagueName
        )
    }

    func timeline(for configuration: SelectLeagueIntent, in context: Context) async -> Timeline<StandingsEntry> {
        let now = Date()
        let resolved = resolveSnapshot(for: configuration)
        let snapshot = resolved.snapshot
        let phase = WidgetPhase.resolve(snapshot: snapshot, now: now)

        if case .preseason = phase, let snapshot, let kickoff = snapshot.seasonKickoffAt {
            let plan = WidgetPhase.preseasonTimeline(kickoff: kickoff, now: now)
            let entries = plan.dates.map {
                StandingsEntry(date: $0, snapshot: snapshot, pendingLeagueName: resolved.pendingLeagueName)
            }
            return Timeline(entries: entries, policy: .after(plan.reload))
        }

        let dates = WidgetPhase.timelineDates(snapshot: snapshot, phase: phase, now: now)
        let entries = dates.map {
            StandingsEntry(date: $0, snapshot: snapshot, pendingLeagueName: resolved.pendingLeagueName)
        }
        return Timeline(
            entries: entries,
            policy: .after(WidgetPhase.reloadDate(phase: phase, dates: dates, now: now))
        )
    }

    private func resolveSnapshot(
        for configuration: SelectLeagueIntent
    ) -> (snapshot: StandingsSnapshot?, pendingLeagueName: String?) {
        if let league = configuration.league {
            PickemsAppGroup.setDisplayGroupId(league.id)
        }
        let loaded = loadSnapshot()
        guard let league = configuration.league else {
            return (loaded, nil)
        }
        if let loaded, loaded.groupId == league.id || loaded.groupId.isEmpty {
            var copy = loaded
            if copy.groupId.isEmpty {
                copy.groupId = league.id
                copy.groupName = league.name
            }
            return (copy, nil)
        }
        if CFBSeasonCalendar.isPreseason(), let loaded {
            var copy = loaded
            copy.groupId = league.id
            copy.groupName = league.name
            return (copy, nil)
        }
        return (nil, league.name)
    }

    /// Prefer App Group data; synthesize a kickoff countdown in preseason even before the app publishes.
    private func loadSnapshot() -> StandingsSnapshot? {
        if CFBSeasonCalendar.isPreseason() {
            let kickoff = CFBSeasonCalendar.nextSeasonKickoff()
            if let loaded = PickemsAppGroup.load() {
                var copy = loaded
                copy.seasonKickoffAt = kickoff
                copy.seasonYear = CFBSeasonCalendar.seasonYear(containing: kickoff)
                return copy
            }
            return .preseasonCountdown(until: kickoff)
        }

        guard var loaded = PickemsAppGroup.load() else { return nil }
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
    var redacted: Bool = false
    /// Set when the widget's league is not the one the app last published.
    var pendingLeagueName: String? = nil
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

    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.widgetFamilyOverride) private var familyOverride
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var systemShowsBackground
    @Environment(\.showsWidgetBackgroundOverride) private var showsBackgroundOverride

    private var family: WidgetFamily { familyOverride ?? systemFamily }
    private var showsBackground: Bool { showsBackgroundOverride ?? systemShowsBackground }

    private var phase: WidgetPhase {
        WidgetPhase.resolve(snapshot: entry.snapshot, now: entry.date)
    }

    private var deepLink: URL? {
        WidgetDeepLink.url(phase: phase, snapshot: entry.snapshot)
    }

    private var rowLinks: Bool {
        switch family {
        case .systemMedium, .systemLarge, .systemExtraLarge:
            return true
        default:
            return false
        }
    }

    private var enlarged: Bool { !showsBackground }

    var body: some View {
        let content = phaseContent
            .redacted(reason: entry.redacted ? .placeholder : [])
            .widgetURL(rowLinks || family == .accessoryInline ? nil : deepLink)
        if renderingMode == .fullColor && showsBackground {
            content.environment(\.colorScheme, .dark)
        } else {
            content
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        if family == .accessoryInline {
            Text(WidgetInlineCopy.text(phase: phase, snapshot: entry.snapshot, now: entry.date))
                .widgetAccentable()
                .widgetURL(deepLink)
                .containerBackground(for: .widget) { Color.clear }
        } else {
            switch phase {
            case .empty:
                emptyState
            case .preseason:
                if let snapshot = entry.snapshot, let kickoff = snapshot.seasonKickoffAt {
                    preseasonContent(snapshot: snapshot, kickoff: kickoff, asOf: entry.date)
                } else {
                    emptyState
                }
            case .deadline(let deadline, let kind):
                if let snapshot = entry.snapshot {
                    DeadlinePhaseView(
                        snapshot: snapshot,
                        deadline: deadline,
                        kind: kind,
                        now: entry.date,
                        linkRows: rowLinks
                    )
                }
            case .scoreboard:
                if let snapshot = entry.snapshot {
                    ScoreboardPhaseView(snapshot: snapshot, now: entry.date, linkRows: rowLinks)
                }
            case .standings:
                if let snapshot = entry.snapshot {
                    standings(snapshot)
                }
            }
        }
    }

    @ViewBuilder
    private func standings(_ snapshot: StandingsSnapshot) -> some View {
        switch family {
        case .systemSmall:
            smallStandings(snapshot).modifier(HomeWidgetBackground(family: family))
        case .systemLarge, .systemExtraLarge:
            largeStandings(snapshot).modifier(HomeWidgetBackground(family: family))
        case .accessoryRectangular:
            rectangularStandings(snapshot).modifier(AccessoryBackground())
        case .accessoryCircular:
            circularStandings(snapshot).modifier(AccessoryBackground())
        default:
            mediumStandings(snapshot).modifier(HomeWidgetBackground(family: family))
        }
    }

    @ViewBuilder
    private func preseasonContent(snapshot: StandingsSnapshot, kickoff: Date, asOf date: Date) -> some View {
        switch family {
        case .systemSmall:
            preseasonHome(snapshot: snapshot, kickoff: kickoff, asOf: date)
                .modifier(HomeWidgetBackground(family: family))
        case .accessoryCircular:
            preseasonCircular(kickoff: kickoff)
                .modifier(AccessoryBackground())
        case .accessoryRectangular:
            preseasonHome(snapshot: snapshot, kickoff: kickoff, asOf: date)
                .modifier(AccessoryBackground())
        default:
            preseasonHome(snapshot: snapshot, kickoff: kickoff, asOf: date)
                .modifier(HomeWidgetBackground(family: family))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let labeled = emptyStack
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(emptyAccessibility)
        if family == .accessoryCircular || family == .accessoryRectangular {
            labeled.modifier(AccessoryBackground())
        } else {
            labeled.modifier(HomeWidgetBackground(family: family))
        }
    }

    private var emptyStack: some View {
        VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            Text("Pickems")
                .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
            if let name = entry.pendingLeagueName {
                Text(name)
                    .font(WidgetStyle.titleFont)
                    .lineLimit(1)
                Text("Open Pickems to see this league")
                    .font(WidgetStyle.rowFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Open Pickems to join a league")
                    .font(WidgetStyle.titleFont)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var emptyAccessibility: String {
        if let name = entry.pendingLeagueName {
            return "Pickems. Open Pickems to see \(name)."
        }
        return "Pickems. Open Pickems to join a league."
    }

    private func preseasonHome(snapshot: StandingsSnapshot, kickoff: Date, asOf date: Date) -> some View {
        VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            WidgetEyebrow(text: snapshot.groupName)
            Text(kickoff, style: .relative)
                .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
            Text("Until kickoff")
                .font(WidgetStyle.titleFont)
                .lineLimit(1)
            Text(kickoff.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(WidgetStyle.rowFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preseasonAccessibilityLabel(snapshot: snapshot, kickoff: kickoff, asOf: date))
    }

    private func preseasonCircular(kickoff: Date) -> some View {
        VStack(spacing: 0) {
            Text(kickoff, style: .relative)
                .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .widgetAccentable()
            Text("KO")
                .font(WidgetStyle.eyebrowFont)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Until college football kickoff")
    }

    private func smallStandings(_ snapshot: StandingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            WidgetEyebrow(text: snapshot.groupName)
            if WidgetPhase.isStale(snapshot: snapshot, now: entry.date) {
                WidgetUpdatedLine(date: snapshot.updatedAt)
            }
            rankHero(snapshot)
            if let back = WidgetStandingsCopy.backOfFirst(snapshot), snapshot.totalPlayers > 0 {
                Text("of \(snapshot.totalPlayers) · \(back)")
                    .font(WidgetStyle.rowFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("Wk \(snapshot.weekNumber) \(snapshot.weeklyRecord) · Season \(snapshot.seasonRecord)")
                .font(WidgetStyle.rowFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    private func mediumStandings(_ snapshot: StandingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    WidgetEyebrow(text: snapshot.groupName)
                    Text("Week \(snapshot.weekNumber)")
                        .font(WidgetStyle.titleFont)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                rankHero(snapshot)
            }
            .widgetLink(rowLinks ? WidgetDeepLink.leaderboardURL(snapshot: snapshot) : nil)
            if let back = WidgetStandingsCopy.backOfFirst(snapshot) {
                Text(back)
                    .font(WidgetStyle.rowFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ForEach(snapshot.topEntries.prefix(3)) { row in
                standingsRow(row, snapshot: snapshot, showSeason: false)
            }
            if WidgetPhase.isStale(snapshot: snapshot, now: entry.date) {
                WidgetUpdatedLine(date: snapshot.updatedAt)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    private func largeStandings(_ snapshot: StandingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: WidgetStyle.rowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    WidgetEyebrow(text: snapshot.groupName)
                    Text("Week \(snapshot.weekNumber)")
                        .font(WidgetStyle.titleFont)
                }
                Spacer(minLength: 8)
                rankHero(snapshot)
            }
            .widgetLink(WidgetDeepLink.leaderboardURL(snapshot: snapshot))
            ForEach(snapshot.topEntries.prefix(8)) { row in
                standingsRow(row, snapshot: snapshot, showSeason: true)
            }
            Spacer(minLength: 0)
            if WidgetPhase.isStale(snapshot: snapshot, now: entry.date) {
                WidgetUpdatedLine(date: snapshot.updatedAt)
                WidgetRefreshButton()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    private func rectangularStandings(_ snapshot: StandingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetEyebrow(text: snapshot.groupName)
            rankHero(snapshot)
            Text("Week \(snapshot.weekNumber) · \(snapshot.weeklyRecord)")
                .font(WidgetStyle.rowFont)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    private func circularStandings(_ snapshot: StandingsSnapshot) -> some View {
        VStack(spacing: 0) {
            Text("#\(snapshot.rank)")
                .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .widgetAccentable()
            Text(snapshot.weeklyRecord)
                .font(WidgetStyle.rowFont)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(standingsAccessibilityLabel(snapshot))
    }

    private func rankHero(_ snapshot: StandingsSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("#\(snapshot.rank)")
                .font(WidgetStyle.heroFont(for: family, enlarged: enlarged))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
            if let delta = WidgetStandingsCopy.deltaSymbol(rank: snapshot.rank, previousRank: snapshot.previousRank) {
                Text(delta)
                    .font(WidgetStyle.titleFont)
                    .foregroundStyle(WidgetStyle.accented(delta.hasPrefix("▲") ? WidgetStyle.winGreen : WidgetStyle.brandRed, mode: renderingMode))
                    .widgetAccentable()
                    .lineLimit(1)
            }
        }
    }

    private func standingsRow(
        _ row: StandingsSnapshot.SnapshotEntry,
        snapshot: StandingsSnapshot,
        showSeason: Bool
    ) -> some View {
        let isYou = row.id == snapshot.userId
        return HStack(spacing: 4) {
            Circle()
                .fill(isYou ? WidgetStyle.accented(WidgetStyle.brandRed, mode: renderingMode) : Color.clear)
                .frame(width: 6, height: 6)
                .widgetAccentable(isYou)
            Text("#\(row.rank)")
                .frame(width: 28, alignment: .leading)
            Text(row.displayName)
                .fontWeight(isYou ? .bold : .regular)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(row.weeklyWins)-\(row.weeklyLosses)")
            if showSeason {
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(row.seasonWins)-\(row.seasonLosses)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(WidgetStyle.rowFont)
        .modifier(YouRowChrome(isYou: isYou))
        .widgetLink(rowLinks ? WidgetDeepLink.leaderboardURL(snapshot: snapshot) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(row, isYou: isYou))
        .accessibilityAddTraits(isYou ? [.isSelected] : [])
    }

    private func standingsAccessibilityLabel(_ snapshot: StandingsSnapshot) -> String {
        let winWord = snapshot.weeklyWins == 1 ? "win" : "wins"
        let lossWord = snapshot.weeklyLosses == 1 ? "loss" : "losses"
        var text = "Week \(snapshot.weekNumber) standings. Rank \(snapshot.rank), \(snapshot.weeklyWins) \(winWord), \(snapshot.weeklyLosses) \(lossWord), \(snapshot.groupName)"
        if let delta = WidgetStandingsCopy.deltaSymbol(rank: snapshot.rank, previousRank: snapshot.previousRank) {
            text += ". Moved \(delta)."
        }
        if let back = WidgetStandingsCopy.backOfFirst(snapshot) {
            text += ". \(back)."
        }
        return text
    }

    private func preseasonAccessibilityLabel(snapshot: StandingsSnapshot, kickoff: Date, asOf date: Date) -> String {
        let summary = CFBSeasonCalendar.countdownSummary(to: kickoff, from: date)
        let day = kickoff.formatted(.dateTime.month(.wide).day())
        return "\(snapshot.groupName). \(summary) until college football kickoff on \(day)."
    }

    private func rowAccessibilityLabel(_ row: StandingsSnapshot.SnapshotEntry, isYou: Bool) -> String {
        let youPrefix = isYou ? "You, " : ""
        return "\(youPrefix)rank \(row.rank), \(row.displayName), \(row.weeklyWins) to \(row.weeklyLosses)"
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
        AppIntentConfiguration(kind: kind, intent: SelectLeagueIntent.self, provider: PickemsWidgetProvider()) { entry in
            PickemsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pickems")
        .description("Deadline countdown, live scoreboard, and standings as the week moves.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}
