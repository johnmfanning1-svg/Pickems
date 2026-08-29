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
    private static var syncGeneration = 0

    static func sync(from appState: AppState) {
        guard #available(iOS 16.2, *) else { return }
        syncGeneration += 1
        let generation = syncGeneration
        Task { await syncAsync(from: appState, generation: generation) }
    }

    static func endAll() async {
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<PickemsLiveAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @available(iOS 16.2, *)
    private static func syncAsync(from appState: AppState, generation: Int) async {
        guard generation == syncGeneration else { return }

        WidgetSnapshotService.dropStaleDisplayPreference(from: appState)

        guard let group = WidgetSnapshotService.resolvedDisplayGroup(from: appState),
              let user = appState.authService.currentUser else {
            await endAll()
            return
        }

        let isSelected = group.id == appState.groupService.selectedGroup?.id
        let week: WeekSummary?
        let ranked: [StandingEntry]
        let nextLabel: String
        let shouldRun: Bool

        if isSelected {
            week = appState.groupService.currentWeek
            ranked = appState.rankedStandings(weekly: true)
            let nextGame = appState.pickService.slateGames
                .filter { $0.status != .final }
                .sorted { $0.kickoff < $1.kickoff }
                .first
            nextLabel = nextGame.map { "\($0.awayTeamAbbreviation) @ \($0.homeTeamAbbreviation)" } ?? "Board settled"
            shouldRun = liveActivityShouldRun(
                week: week,
                pickingHasLiveGame: appState.pickService.slateGames.contains { $0.status == .inProgress }
            )
        } else {
            let fetched = await appState.groupService.fetchStandings(groupId: group.id)
            guard generation == syncGeneration else { return }
            week = fetched.week
            ranked = WidgetSnapshotService.rankedDisplayEntries(
                standings: fetched.standings,
                members: fetched.members,
                tieBreaker: group.rules.tieBreaker
            )
            nextLabel = "This week's slate"
            shouldRun = liveActivityShouldRun(week: week, pickingHasLiveGame: false)
        }

        guard let week else {
            await endAll()
            return
        }

        if !shouldRun {
            await endAll()
            return
        }

        let mine = ranked.first(where: { $0.id == user.id })
        let state = PickemsLiveAttributes.ContentState(
            weeklyWins: mine?.weeklyWins ?? 0,
            weeklyLosses: mine?.weeklyLosses ?? 0,
            rank: mine?.rank ?? ranked.count,
            totalPlayers: ranked.count,
            nextGameLabel: nextLabel,
            updatedAt: Date()
        )
        let attributes = PickemsLiveAttributes(
            groupName: group.name,
            weekNumber: week.weekNumber,
            userDisplayName: user.displayName
        )
        await upsert(attributes: attributes, state: state)
    }

    private static func liveActivityShouldRun(week: WeekSummary?, pickingHasLiveGame: Bool) -> Bool {
        guard let week else { return false }
        if week.status == .locked { return true }
        return week.status == .picking && pickingHasLiveGame
    }

    @available(iOS 16.2, *)
    private static func upsert(
        attributes: PickemsLiveAttributes,
        state: PickemsLiveAttributes.ContentState
    ) async {
        let content = ActivityContent(state: state, staleDate: nil)
        if let existing = Activity<PickemsLiveAttributes>.activities.first {
            let sameLeague = existing.attributes.groupName == attributes.groupName
                && existing.attributes.weekNumber == attributes.weekNumber
                && existing.attributes.userDisplayName == attributes.userDisplayName
            if sameLeague {
                await existing.update(content)
                return
            }
            await endAll()
        }
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            // Live Activities may be disabled by the user.
        }
    }
}
