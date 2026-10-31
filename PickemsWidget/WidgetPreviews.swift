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
        return snapshot
    }

    static var pickemsDeadlinePreview: StandingsSnapshot {
        var snapshot = previewBase(name: "Saturday Crew", wins: 0, losses: 0, rank: 4)
        snapshot.pickemsDeadline = Date().addingTimeInterval(6 * 3_600)
        snapshot.games = [previewGame(index: 0, kickoff: Date().addingTimeInterval(6 * 3_600))]
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
            result: final || (started && index % 3 == 0) ? (index % 2 == 0 ? .win : .loss) : result
        )
    }
}

private func previewEntry(_ snapshot: StandingsSnapshot?) -> StandingsEntry {
    StandingsEntry(date: Date(), snapshot: snapshot)
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
