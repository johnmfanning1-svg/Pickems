import Foundation

extension AppState {
    func weeklyShareSource() -> ShareSource? {
        guard
            let user = authService.currentUser,
            let group = groupService.selectedGroup,
            let week = groupService.currentWeek,
            let entry = rankedStandings(weekly: true).first(where: { $0.id == user.id })
        else { return nil }

        let season = groupService.cfbWeek?.seasonYear ?? Calendar.current.component(.year, from: Date())
        let totalPicks = entry.weeklyWins + entry.weeklyLosses

        return SharingIntegration.weeklySource(
            userId: user.id,
            displayName: user.displayName,
            week: week.weekNumber,
            season: season,
            leagueName: group.name,
            correctPicks: entry.weeklyWins,
            totalPicks: totalPicks,
            rank: entry.rank,
            totalPlayers: group.memberCount,
            isWeeklyWinner: entry.rank == 1 && !entry.isTied
        )
    }

    func seasonShareSource() -> ShareSource? {
        guard
            let user = authService.currentUser,
            let group = groupService.selectedGroup,
            let entry = rankedStandings(weekly: false).first(where: { $0.id == user.id })
        else { return nil }

        let season = groupService.cfbWeek?.seasonYear ?? Calendar.current.component(.year, from: Date())

        return SharingIntegration.seasonSource(
            userId: user.id,
            displayName: user.displayName,
            season: season,
            leagueName: group.name,
            totalPoints: entry.seasonWins,
            weeklyWins: entry.seasonWins,
            rank: entry.rank,
            totalPlayers: group.memberCount
        )
    }
}
