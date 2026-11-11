import WidgetKit
import SwiftUI

extension StandingsSnapshot {
    static var deadlinePreview: StandingsSnapshot {
        var snapshot = previewBase(
            name: "Saturday Morning Quarterbacks International",
            wins: 0,
            losses: 0,
            rank: 0
        )
        snapshot.selectionsDeadline = Date().addingTimeInterval(18 * 3_600 + 24 * 60)
        snapshot.pickemsDeadline = Date().addingTimeInterval(42 * 3_600)
        snapshot.selectionQuota = WidgetSelectionQuota.member
        snapshot.selectionsMade = 2
        snapshot.selectionsTotal = 2
        snapshot.selectionMembersDone = 6
        snapshot.selectionMembersTotal = 11
        snapshot.selectionGamesFilled = 12
        snapshot.selectionGamesTarget = 22
        snapshot.picksMade = 0
        snapshot.picksTotal = 4
        snapshot.games = (0..<2).map { index in
            var game = previewGame(index: index, kickoff: Date().addingTimeInterval(42 * 3_600))
            game.userPick = nil
            game.isUserSelection = true
            return game
        }
        return snapshot
    }

    static var pickemsDeadlinePreview: StandingsSnapshot {
        var snapshot = previewBase(name: "Saturday Crew", wins: 0, losses: 0, rank: 4)
        snapshot.pickemsDeadline = Date().addingTimeInterval(2 * 3_600 + 14 * 60)
        snapshot.picksMade = 7
        snapshot.picksTotal = 10
        snapshot.games = [previewGame(index: 0, kickoff: Date().addingTimeInterval(2 * 3_600 + 14 * 60))]
        return snapshot
    }

    static var scoreboardPreview: StandingsSnapshot {
        var snapshot = previewBase(
            name: "Saturday Morning Quarterbacks International",
            wins: 3,
            losses: 1,
            rank: 4
        )
        snapshot.rollingLock = true
        snapshot.pickemsDeadline = Date().addingTimeInterval(-3_600)
        snapshot.games = (0..<12).map { index in
            previewGame(index: index, kickoff: Date().addingTimeInterval(TimeInterval((index - 2) * 3_600)))
        }
        return snapshot
    }

    static var standingsPreview: StandingsSnapshot {
        var snapshot = previewBase(
            name: "Saturday Morning Quarterbacks International",
            wins: 4,
            losses: 2,
            rank: 2
        )
        snapshot.topEntries = [
            .init(id: "1", displayName: "Alexandria Montgomery", weeklyWins: 5, weeklyLosses: 1, seasonWins: 30, seasonLosses: 12, rank: 1),
            .init(id: "u", displayName: "You", weeklyWins: 4, weeklyLosses: 2, seasonWins: 28, seasonLosses: 14, rank: 2),
            .init(id: "3", displayName: "Christopher Williamson", weeklyWins: 3, weeklyLosses: 3, seasonWins: 25, seasonLosses: 17, rank: 3),
            .init(id: "4", displayName: "Sam", weeklyWins: 2, weeklyLosses: 4, seasonWins: 18, seasonLosses: 20, rank: 4),
        ]
        snapshot.previousRank = 4
        snapshot.games = [
            previewGame(index: 0, kickoff: Date().addingTimeInterval(-86_400), final: true, result: .win),
            previewGame(index: 1, kickoff: Date().addingTimeInterval(-80_000), final: true, result: .loss),
        ]
        return snapshot
    }

    static var preseasonPreview: StandingsSnapshot {
        var snapshot = previewBase(name: "Pickems", wins: 0, losses: 0, rank: 0)
        snapshot.seasonKickoffAt = Date().addingTimeInterval(12 * 86_400)
        return snapshot
    }

    private static func previewBase(name: String, wins: Int, losses: Int, rank: Int) -> StandingsSnapshot {
        StandingsSnapshot(
            groupId: "league-1",
            groupName: name,
            weekNumber: 6,
            seasonYear: 2026,
            userId: "u",
            userDisplayName: "You",
            weeklyWins: wins,
            weeklyLosses: losses,
            seasonWins: 28,
            seasonLosses: 14,
            rank: rank,
            totalPlayers: 8,
            topEntries: [],
            updatedAt: Date()
        )
    }

    private static func previewGame(
        index: Int,
        kickoff: Date,
        final: Bool = false,
        result: SnapshotPickResult = .pending
    ) -> SnapshotGame {
        let away = ["Coastal Carolina", "Appalachian State", "Jacksonville State", "Middle Tennessee"][index % 4]
        let home = ["Florida Atlantic", "Georgia Southern", "Texas State", "Old Dominion"][index % 4]
        let started = kickoff <= Date()
        return SnapshotGame(
            id: "game-\(index)",
            awayShortName: away,
            homeShortName: home,
            kickoff: kickoff,
            isLocked: started,
            isFinal: final || (started && index % 3 == 0),
            awayScore: started ? 17 + index : nil,
            homeScore: started ? 21 : nil,
            userPick: index % 2 == 0 ? away : home,
            result: final || (started && index % 3 == 0) ? (index % 2 == 0 ? .win : .loss) : result,
            awayColorHex: "#BA0C2F",
            homeColorHex: "#00274C",
            statusText: (final || (started && index % 3 == 0)) ? "Final" : (started ? "Q3 4:12" : "Sat 3:30")
        )
    }
}

extension StandingsSnapshot {
    /// Widget gallery snapshot. One sample per family, richer than the redacted placeholder.
    static func gallerySample(for family: WidgetFamily) -> StandingsSnapshot {
        switch family {
        case .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular:
            return scoreboardPreview
        default:
            return pickemsDeadlinePreview
        }
    }
}

private func previewEntry(_ snapshot: StandingsSnapshot?) -> StandingsEntry {
    StandingsEntry(date: Date(), snapshot: snapshot)
}

private struct WidgetModeCanvas: View {
    var entry: StandingsEntry
    var family: WidgetFamily
    var mode: WidgetRenderingMode
    var showsBackground: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PickemsWidgetEntryView(entry: entry)
            .environment(\.widgetFamilyOverride, family)
            .environment(\.widgetRenderingMode, mode)
            .environment(\.showsWidgetBackgroundOverride, showsBackground)
            .frame(width: width, height: height)
            .background(showsBackground && mode == .fullColor ? WidgetStyle.canvas(AppearancePreferenceStore.resolvedColorScheme() ?? colorScheme) : Color.gray.opacity(0.35))
    }

    private var width: CGFloat {
        switch family {
        case .systemSmall: return 170
        case .systemMedium: return 360
        case .systemLarge: return 360
        default: return 170
        }
    }

    private var height: CGFloat {
        switch family {
        case .systemSmall: return 170
        case .systemMedium: return 170
        case .systemLarge: return 376
        default: return 72
        }
    }
}

#Preview("Deadline · Small", as: .systemSmall) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.deadlinePreview)
}

#Preview("Deadline · Medium", as: .systemMedium) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.deadlinePreview)
}

#Preview("Deadline · Large", as: .systemLarge) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.deadlinePreview)
}

#Preview("Deadline · Rectangular", as: .accessoryRectangular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.pickemsDeadlinePreview)
}

#Preview("Deadline · Circular", as: .accessoryCircular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.deadlinePreview)
}

#Preview("Scoreboard · Small", as: .systemSmall) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.scoreboardPreview)
}

#Preview("Scoreboard · Medium", as: .systemMedium) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.scoreboardPreview)
}

#Preview("Scoreboard · Large", as: .systemLarge) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.scoreboardPreview)
}

#Preview("Scoreboard · Rectangular", as: .accessoryRectangular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.scoreboardPreview)
}

#Preview("Scoreboard · Circular", as: .accessoryCircular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.scoreboardPreview)
}

#Preview("Standings · Small", as: .systemSmall) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.standingsPreview)
}

#Preview("Standings · Medium", as: .systemMedium) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.standingsPreview)
}

#Preview("Standings · Large", as: .systemLarge) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.standingsPreview)
}

#Preview("Standings · Rectangular", as: .accessoryRectangular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.standingsPreview)
}

#Preview("Standings · Circular", as: .accessoryCircular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.standingsPreview)
}

#Preview("Preseason · Small", as: .systemSmall) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.preseasonPreview)
}

#Preview("Preseason · Medium", as: .systemMedium) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.preseasonPreview)
}

#Preview("Preseason · Large", as: .systemLarge) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.preseasonPreview)
}

#Preview("Preseason · Rectangular", as: .accessoryRectangular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.preseasonPreview)
}

#Preview("Preseason · Circular", as: .accessoryCircular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.preseasonPreview)
}

#Preview("Empty · Small", as: .systemSmall) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(nil)
}

#Preview("Empty · Medium", as: .systemMedium) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(nil)
}

#Preview("Empty · Large", as: .systemLarge) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(nil)
}

#Preview("Empty · Rectangular", as: .accessoryRectangular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(nil)
}

#Preview("Empty · Circular", as: .accessoryCircular) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(nil)
}

#Preview("Deadline · Inline", as: .accessoryInline) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.pickemsDeadlinePreview)
}

#Preview("Scoreboard · Inline", as: .accessoryInline) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.scoreboardPreview)
}

#Preview("Standings · Inline", as: .accessoryInline) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.standingsPreview)
}

#Preview("Preseason · Inline", as: .accessoryInline) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(.preseasonPreview)
}

#Preview("Empty · Inline", as: .accessoryInline) {
    PickemsStandingsWidget()
} timeline: {
    previewEntry(nil)
}

#Preview("Placeholder · Small", as: .systemSmall) {
    PickemsStandingsWidget()
} timeline: {
    StandingsEntry(date: Date(), snapshot: .placeholder, redacted: true)
}

#Preview("Modes · Full color") {
    WidgetModeCanvas(entry: previewEntry(.pickemsDeadlinePreview), family: .systemSmall, mode: .fullColor)
}

#Preview("Modes · Accented") {
    WidgetModeCanvas(entry: previewEntry(.scoreboardPreview), family: .systemMedium, mode: .accented)
}

#Preview("Modes · Vibrant") {
    WidgetModeCanvas(entry: previewEntry(.standingsPreview), family: .systemSmall, mode: .vibrant)
}

#Preview("Modes · StandBy") {
    WidgetModeCanvas(
        entry: previewEntry(.pickemsDeadlinePreview),
        family: .systemSmall,
        mode: .fullColor,
        showsBackground: false
    )
}
