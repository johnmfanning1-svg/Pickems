import Foundation

extension AppState {
    func weeklyShareSource() -> ShareSource? {
        guard
            let user = authService.currentUser,
            let group = groupService.selectedGroup,
            let week = groupService.currentWeek
        else { return nil }

        let ranked = rankedStandings(weekly: true)
        guard let entry = ranked.first(where: { $0.id == user.id }) else { return nil }

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
            totalPlayers: max(ranked.count, 1),
            isWeeklyWinner: entry.rank == 1 && !entry.isTied
        )
    }

    func weeklyShareSource(week: WeekSummary, ranked: [StandingEntry]) -> ShareSource? {
        guard
            let user = authService.currentUser,
            let group = groupService.selectedGroup,
            let entry = ranked.first(where: { $0.id == user.id })
        else { return nil }

        let totalPicks = entry.weeklyWins + entry.weeklyLosses
        guard totalPicks > 0 || week.status == .scored else { return nil }

        return SharingIntegration.weeklySource(
            userId: user.id,
            displayName: user.displayName,
            week: week.weekNumber,
            season: week.seasonYear,
            leagueName: group.name,
            correctPicks: entry.weeklyWins,
            totalPicks: totalPicks,
            rank: entry.rank,
            totalPlayers: max(ranked.count, 1),
            isWeeklyWinner: entry.rank == 1 && !entry.isTied
        )
    }

    func seasonShareSource() -> ShareSource? {
        guard
            let user = authService.currentUser,
            let group = groupService.selectedGroup
        else { return nil }

        let ranked = rankedStandings(weekly: false)
        guard let entry = ranked.first(where: { $0.id == user.id }) else { return nil }

        let season = groupService.cfbWeek?.seasonYear ?? Calendar.current.component(.year, from: Date())

        return SharingIntegration.seasonSource(
            userId: user.id,
            displayName: user.displayName,
            season: season,
            leagueName: group.name,
            totalPoints: entry.seasonWins,
            weeklyWins: 0,
            rank: entry.rank,
            totalPlayers: max(ranked.count, 1)
        )
    }
}
