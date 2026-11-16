import Foundation

@MainActor
@Observable
final class SeasonLedgerLoader {
    private(set) var data: SeasonLedgerSeasonData?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var cachedGroupId: String?
    private static var seasonCache: [String: SeasonLedgerSeasonData] = [:]
    private static let weekFetchLimit = 64
    private static let parallelWeekCap = 6

    func loadIfNeeded(
        appState: AppState,
        forceRefresh: Bool = false
    ) async {
        guard let group = appState.groupService.selectedGroup else {
            data = nil
            errorMessage = nil
            return
        }
        if !forceRefresh, cachedGroupId == group.id, let data {
            self.data = data
            return
        }
        if !forceRefresh, let cached = Self.seasonCache[group.id] {
            data = cached
            cachedGroupId = group.id
            return
        }
        await reload(appState: appState)
    }

    func reload(appState: AppState) async {
        guard let group = appState.groupService.selectedGroup else {
            data = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let built = try await Self.buildSeason(
                groupId: group.id,
                leaguePickMode: group.rules.pickMode,
                members: appState.groupService.members,
                viewerId: appState.currentUserId,
                pickService: appState.pickService,
                groupService: appState.groupService
            )
            data = built
            cachedGroupId = group.id
            Self.seasonCache[group.id] = built
        } catch {
            data = nil
            errorMessage = UserFacingError.message(for: error, context: .generic)
                ?? error.localizedDescription
        }
    }

    static func invalidate(groupId: String) {
        seasonCache.removeValue(forKey: groupId)
    }

    private static func buildSeason(
        groupId: String,
        leaguePickMode: PickMode,
        members: [GroupMember],
        viewerId: String?,
        pickService: PickService,
        groupService: GroupService
    ) async throws -> SeasonLedgerSeasonData {
        let fetched = try await groupService.fetchPastWeeks(groupId: groupId, limit: Self.weekFetchLimit)
        let eligible = fetched
            .filter { week in
                week.status == .scored
                    || week.status == .locked
                    || WeekTransition.pickemsShouldShowLeagueBoard(week)
            }
            .sorted {
                if $0.seasonYear != $1.seasonYear { return $0.seasonYear < $1.seasonYear }
                return $0.weekNumber < $1.weekNumber
            }

        var boards: [SeasonLedgerWeekBoard] = []
        boards.reserveCapacity(eligible.count)

        var index = 0
        while index < eligible.count {
            let batch = Array(eligible[index..<min(index + Self.parallelWeekCap, eligible.count)])
            let batchBoards = try await withThrowingTaskGroup(of: SeasonLedgerWeekBoard?.self) { group in
                for week in batch {
                    group.addTask {
                        try await Self.loadWeekBoard(
                            week: week,
                            groupId: groupId,
                            leaguePickMode: leaguePickMode,
                            members: members,
                            viewerId: viewerId,
                            pickService: pickService,
                            groupService: groupService
                        )
                    }
                }
                var results: [SeasonLedgerWeekBoard] = []
                for try await board in group {
                    if let board { results.append(board) }
                }
                return results
            }
            boards.append(contentsOf: batchBoards.sorted { $0.week.weekNumber < $1.week.weekNumber })
            index += Self.parallelWeekCap
        }

        boards.sort {
            if $0.week.seasonYear != $1.week.seasonYear { return $0.week.seasonYear < $1.week.seasonYear }
            return $0.week.weekNumber < $1.week.weekNumber
        }

        return SeasonLedgerSeasonData(
            groupId: groupId,
            weeks: boards,
            memberIds: members.map(\.id)
        )
    }

    private static func loadWeekBoard(
        week: WeekSummary,
        groupId: String,
        leaguePickMode: PickMode,
        members: [GroupMember],
        viewerId: String?,
        pickService: PickService,
        groupService: GroupService
    ) async throws -> SeasonLedgerWeekBoard? {
        let snapshot = try await pickService.fetchLeagueBoard(groupId: groupId, weekId: week.id)
        var games = snapshot.games
        var picks = snapshot.picks
        let resolvedWeek = snapshot.week

        if resolvedWeek.id == groupService.currentWeek?.id, groupService.selectedGroup?.id == groupId {
            if !pickService.slateGames.isEmpty {
                games = pickService.slateGames.sortedByKickoff
            }
            picks = PickService.mergingRevealedPicks(
                base: pickService.allPicks.isEmpty ? picks : pickService.allPicks,
                revealed: pickService.revealedPicksByGameId,
                members: members
            )
            if let own = pickService.userPick {
                var map = Dictionary(uniqueKeysWithValues: picks.map { ($0.userId, $0) })
                map[own.userId] = own
                picks = Array(map.values)
            }
        }

        let pickMode = resolvedWeek.resolvedPickMode(leagueMode: leaguePickMode)
        let hidden = SeasonLedgerPrivacy.hiddenGameIds(week: resolvedWeek, games: games)
        let picksByUserId = Dictionary(uniqueKeysWithValues: picks.map { ($0.userId, $0) })

        let records = SeasonLedgerAggregator.memberRecords(
            members: members,
            games: games,
            picksByUserId: picksByUserId,
            hiddenGameIds: hidden,
            viewerId: viewerId,
            pickMode: pickMode
        )

        return SeasonLedgerWeekBoard(
            week: resolvedWeek,
            games: games,
            picksByUserId: picksByUserId,
            hiddenGameIds: hidden,
            recordsByMemberId: records,
            pickMode: pickMode
        )
    }
}