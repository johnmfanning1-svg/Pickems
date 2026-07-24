import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    static func publish(from appState: AppState) {
        if CFBSeasonCalendar.isPreseason() {
            publishPreseason(from: appState)
            return
        }
        publishStandings(from: appState)
    }

    private static func publishPreseason(from appState: AppState) {
        let kickoff = CFBSeasonCalendar.nextWeekZeroStart()
        let seasonYear = CFBSeasonCalendar.seasonYear(containing: kickoff)
        let group = appState.groupService.selectedGroup
        let user = appState.authService.currentUser

        let snapshot = StandingsSnapshot(
            groupId: group?.id ?? "",
            groupName: group?.name ?? "Pickems",
            weekNumber: 0,
            seasonYear: seasonYear,
            userId: user?.id ?? "",
            userDisplayName: user?.displayName ?? "You",
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
        PickemsAppGroup.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func publishStandings(from appState: AppState) {
        guard let group = appState.groupService.selectedGroup,
              let user = appState.authService.currentUser,
              let standings = appState.groupService.standings else {
            // In-season but no standings yet — still clear any stale preseason countdown.
            if var stale = PickemsAppGroup.load(), stale.seasonKickoffAt != nil {
                stale.seasonKickoffAt = nil
                PickemsAppGroup.save(stale)
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }

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
            updatedAt: Date(),
            seasonKickoffAt: nil
        )
        PickemsAppGroup.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
