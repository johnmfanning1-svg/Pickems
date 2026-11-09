import ActivityKit
import Foundation

@MainActor
enum LiveActivityController {
    private static var syncGeneration = 0
    private static var suspended = false
    private static var acceptingTokens = true
    private static var tokensDesired = false
    private static var tokenTasks: [String: Task<Void, Never>] = [:]
    private static var tokenChain: Task<Void, Never>?
    private static var lastToken: (userId: String, token: String, key: String)?

    static func sync(from appState: AppState) {
        guard !suspended else { return }
        guard #available(iOS 16.2, *) else { return }
        syncGeneration += 1
        let generation = syncGeneration
        Task { await syncAsync(from: appState, generation: generation) }
    }

    /// Sign-out. Later `sync` calls do nothing until `resume()` on the next session.
    static func suspend() {
        suspended = true
        acceptingTokens = false
        tokensDesired = false
        syncGeneration += 1
        lastToken = nil
        tokenTasks.values.forEach { $0.cancel() }
        tokenTasks.removeAll()
    }

    static func resume() {
        suspended = false
        acceptingTokens = true
    }

    static func endAll() async {
        await endActivities()
    }

    static func drainTokenWrites() async {
        await tokenChain?.value
    }

    @available(iOS 16.2, *)
    private static func syncAsync(from appState: AppState, generation: Int) async {
        guard generation == syncGeneration, !suspended else { return }

        WidgetSnapshotService.dropStaleDisplayPreference(from: appState)

        let signedIn = appState.authService.currentUser
        guard let group = WidgetSnapshotService.resolvedDisplayGroup(from: appState),
              let user = signedIn else {
            tokensDesired = false
            await endActivities()
            if let signedIn {
                await clearToken(userId: signedIn.id)
            }
            return
        }

        let loaded = await load(
            appState: appState,
            group: group,
            userId: user.id,
            displayName: user.displayName,
            generation: generation
        )
        guard generation == syncGeneration, !suspended else { return }

        switch loaded {
        case .unavailable:
            return
        case .absent:
            tokensDesired = false
            await endActivities()
            await clearToken(userId: user.id)
            return
        case .ready(let context):
            let shouldRun = LiveActivityContent.shouldRun(
                weekStatus: context.week.status,
                pickingHasLiveGame: context.games.contains { $0.status == .inProgress }
            )
            guard shouldRun else {
                tokensDesired = false
                await endActivities()
                await clearToken(userId: user.id)
                return
            }
            guard generation == syncGeneration, !suspended else { return }
            let mine = context.ranked.first { $0.id == context.userId }
            let boardDecided = (mine?.weeklyWins ?? 0) + (mine?.weeklyLosses ?? 0)
            let penalty = (!context.week.isRollingLock && context.group.rules.allowLatePicks)
                ? max(0, context.group.rules.latePickPenaltyWins)
                : 0
            let state = LiveActivityContent.build(
                games: context.games,
                picks: context.pick?.picks ?? [:],
                pickMode: context.week.resolvedPickMode(leagueMode: context.group.rules.pickMode),
                confidenceGameId: context.pick?.confidenceGameId,
                submittedAt: context.pick?.submittedAt,
                deadline: context.week.pickDeadline,
                latePenaltyWins: penalty,
                rank: boardDecided > 0 ? mine?.rank : nil,
                rankTied: mine.map { entry in
                    context.ranked.contains { $0.id != entry.id && $0.rank == entry.rank }
                } ?? false,
                rankBoardDecidedGames: boardDecided,
                updatedAt: Date()
            )
            let attributes = PickemsLiveAttributes(
                groupId: context.group.id,
                groupName: context.group.name,
                weekId: context.weekId,
                weekNumber: context.week.weekNumber,
                userDisplayName: context.displayName
            )
            tokensDesired = true
            acceptingTokens = true
            await upsert(attributes: attributes, state: state, userId: context.userId)
        }
    }

    private struct Context {
        var group: PickemGroup
        var weekId: String
        var week: WeekSummary
        var games: [SlateGame]
        var pick: UserPick?
        var ranked: [StandingEntry]
        var userId: String
        var displayName: String
    }

    private enum LoadResult {
        case ready(Context)
        case unavailable
        case absent
    }

    private static func load(
        appState: AppState,
        group: PickemGroup,
        userId: String,
        displayName: String,
        generation: Int
    ) async -> LoadResult {
        if appState.groupService.selectedGroup?.id == group.id,
           let week = appState.groupService.currentWeek,
           !week.id.isEmpty,
           appState.pickService.observingGroupId == group.id,
           appState.pickService.observedWeekId == week.id {
            return .ready(Context(
                group: group,
                weekId: week.id,
                week: week,
                games: appState.pickService.slateGames,
                pick: appState.pickService.userPick,
                ranked: appState.rankedStandings(weekly: true),
                userId: userId,
                displayName: displayName
            ))
        }

        let fetched = await appState.groupService.fetchStandings(groupId: group.id)
        guard generation == syncGeneration, !suspended else { return .unavailable }
        guard let week = fetched.week, !week.id.isEmpty else { return .absent }
        let history: WeekHistoryEntry?
        do {
            history = try await appState.pickService.loadWeekHistory(
                groupId: group.id,
                weekId: week.id,
                userId: userId
            )
        } catch {
            AppLog.error(AppLog.notifications, "Live Activity slate fetch failed", error: error, metadata: [
                "group_id": group.id,
            ])
            return .unavailable
        }
        guard let history else { return .absent }
        let ranked = WidgetSnapshotService.rankedDisplayEntries(
            standings: fetched.standings,
            members: fetched.members,
            memberIds: group.memberIds,
            tieBreaker: group.rules.tieBreaker,
            tieBreakOrder: week.tieBreakOrder ?? [],
            displayedWeekNumber: week.weekNumber
        )
        return .ready(Context(
            group: group,
            weekId: history.id,
            week: history.week,
            games: history.slateGames,
            pick: history.userPick,
            ranked: ranked,
            userId: userId,
            displayName: displayName
        ))
    }

    @available(iOS 16.2, *)
    private static func upsert(
        attributes: PickemsLiveAttributes,
        state: PickemsLiveAttributes.ContentState,
        userId: String
    ) async {
        let content = activityContent(for: state)
        let existing = Activity<PickemsLiveAttributes>.activities
        if let match = existing.first(where: {
            $0.attributes.groupId == attributes.groupId
                && $0.attributes.weekId == attributes.weekId
                && !$0.attributes.groupId.isEmpty
                && $0.content.state.contentVersion >= LiveActivitySchema.version
        }) {
            for activity in existing where activity.id != match.id {
                tokenTasks[activity.id]?.cancel()
                tokenTasks[activity.id] = nil
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            await match.update(content)
            watchPushToken(match, userId: userId)
            return
        }
        await endActivities()
        guard !suspended else { return }
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            watchPushToken(activity, userId: userId)
        } catch {
            AppLog.error(AppLog.notifications, "Live Activity request failed", error: error)
        }
    }

    @available(iOS 16.2, *)
    private static func activityContent(
        for state: PickemsLiveAttributes.ContentState
    ) -> ActivityContent<PickemsLiveAttributes.ContentState> {
        let live = state.picks.contains { $0.phase == "live" }
        let upcoming = state.picks.contains { $0.phase == "upcoming" }
        let relevance = live ? 100.0 : (upcoming ? 50.0 : 15.0)
        let stale = Date(timeIntervalSince1970: state.updatedAt).addingTimeInterval(20 * 60)
        return ActivityContent(state: state, staleDate: stale, relevanceScore: relevance)
    }

    @available(iOS 16.2, *)
    private static func watchPushToken(_ activity: Activity<PickemsLiveAttributes>, userId: String) {
        guard tokenTasks[activity.id] == nil else { return }
        let groupId = activity.attributes.groupId
        let weekId = activity.attributes.weekId
        tokenTasks[activity.id] = Task {
            if let current = activity.pushToken {
                await persist(current, userId: userId, groupId: groupId, weekId: weekId)
            }
            for await token in activity.pushTokenUpdates {
                if Task.isCancelled || suspended { return }
                await persist(token, userId: userId, groupId: groupId, weekId: weekId)
            }
        }
    }

    private static func persist(_ token: Data, userId: String, groupId: String, weekId: String) async {
        guard acceptingTokens, tokensDesired, !suspended else { return }
        let hex = token.map { String(format: "%02x", Int($0)) }.joined()
        guard !hex.isEmpty else { return }
        let key = LiveActivitySchema.activityKey(groupId: groupId, weekId: weekId)
        enqueueTokenWrite {
            guard acceptingTokens, tokensDesired, !suspended else { return }
            if lastToken?.userId == userId, lastToken?.token == hex, lastToken?.key == key { return }
            await LiveActivityTokenStore.save(userId: userId, token: hex, groupId: groupId, weekId: weekId)
            guard acceptingTokens, tokensDesired, !suspended else { return }
            lastToken = (userId, hex, key)
        }
    }

    private static func clearToken(userId: String) async {
        lastToken = nil
        enqueueTokenWrite {
            guard !tokensDesired else { return }
            await LiveActivityTokenStore.clear(userId: userId)
        }
        await drainTokenWrites()
    }

    private static func enqueueTokenWrite(_ body: @escaping @MainActor () async -> Void) {
        let previous = tokenChain
        let next = Task { @MainActor in
            await previous?.value
            await body()
        }
        tokenChain = next
    }

    private static func endActivities() async {
        tokenTasks.values.forEach { $0.cancel() }
        tokenTasks.removeAll()
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<PickemsLiveAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
