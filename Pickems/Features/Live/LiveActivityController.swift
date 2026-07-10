import ActivityKit
import Foundation

struct PickemsLiveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var weeklyWins: Int
        var weeklyLosses: Int
        var rank: Int
        var totalPlayers: Int
        var nextGameLabel: String
        var updatedAt: Date
    }

    var groupName: String
    var weekNumber: Int
    var userDisplayName: String
}

@MainActor
enum LiveActivityController {
    static func sync(from appState: AppState) {
        guard #available(iOS 16.2, *) else { return }
        guard let group = appState.groupService.selectedGroup,
              let week = appState.groupService.currentWeek,
              let user = appState.authService.currentUser else { return }

        let shouldRun = week.status == .locked || (week.status == .picking && appState.pickService.slateGames.contains { $0.status == .inProgress })
        let ranked = appState.rankedStandings(weekly: true)
        let mine = ranked.first(where: { $0.id == user.id })
        let nextGame = appState.pickService.slateGames
            .filter { $0.status != .final }
            .sorted { $0.kickoff < $1.kickoff }
            .first
        let nextLabel = nextGame.map { "\($0.awayTeamAbbreviation) @ \($0.homeTeamAbbreviation)" } ?? "Board settled"

        let state = PickemsLiveAttributes.ContentState(
            weeklyWins: mine?.weeklyWins ?? 0,
            weeklyLosses: mine?.weeklyLosses ?? 0,
            rank: mine?.rank ?? ranked.count,
            totalPlayers: ranked.count,
            nextGameLabel: nextLabel,
            updatedAt: Date()
        )

        if !shouldRun {
            Task { await endAll() }
            return
        }

        let attributes = PickemsLiveAttributes(
            groupName: group.name,
            weekNumber: week.weekNumber,
            userDisplayName: user.displayName
        )

        if let existing = Activity<PickemsLiveAttributes>.activities.first {
            Task { await existing.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                // Live Activities may be disabled by the user.
            }
        }
    }

    static func endAll() async {
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<PickemsLiveAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
