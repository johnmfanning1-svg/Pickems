import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    static func publish(from appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let user = appState.authService.currentUser,
              let standings = appState.groupService.standings else { return }

        let ranked = appState.rankedStandings(weekly: true)
        guard let mine = ranked.first(where: { $0.id == user.id }) ?? standings.entries.first(where: { $0.id == user.id }) else {
            return
        }

        let snapshot = StandingsSnapshot(
            groupId: group.id,
            groupName: group.name,
            weekNumber: standings.weekNumber,
            seasonYear: appState.groupService.currentWeek?.seasonYear
                ?? appState.groupService.cfbWeek?.seasonYear
                ?? Calendar.current.component(.year, from: Date()),
            userId: user.id,
            userDisplayName: user.displayName,
            weeklyWins: mine.weeklyWins,
            weeklyLosses: mine.weeklyLosses,
            seasonWins: mine.seasonWins,
            seasonLosses: mine.seasonLosses,
            rank: mine.rank,
            totalPlayers: ranked.count,
            topEntries: ranked.prefix(5).map {
                .init(
                    id: $0.id,
                    displayName: $0.displayName,
                    weeklyWins: $0.weeklyWins,
                    weeklyLosses: $0.weeklyLosses,
                    seasonWins: $0.seasonWins,
                    seasonLosses: $0.seasonLosses,
                    rank: $0.rank
                )
            },
            updatedAt: Date()
        )
        PickemsAppGroup.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
