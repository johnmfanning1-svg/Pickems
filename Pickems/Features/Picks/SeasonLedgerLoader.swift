import Foundation

/// MainActor-free refresh failure presentation for Season Ledger tests and views.
enum SeasonLedgerRefreshPresentation {
    /// Shown when a refresh fails but the last loaded ledger is still on screen.
    static let staleRefreshBannerMessage =
        "Couldn't refresh. Showing the last loaded ledger."

    static func cacheKey(groupId: String, viewerId: String?) -> String {
        "\(groupId)|\(viewerId ?? "")"
    }

    static func showsRefreshFailureBanner(
        errorMessage: String?,
        data: SeasonLedgerSeasonData?
    ) -> Bool {
        guard errorMessage != nil, let data, !data.weeks.isEmpty else { return false }
        return true
    }

    static func showsFullLoadError(
        errorMessage: String?,
        data: SeasonLedgerSeasonData?,
        isLoading: Bool
    ) -> Bool {
        guard errorMessage != nil else { return false }
        if showsRefreshFailureBanner(errorMessage: errorMessage, data: data) { return false }
        if isLoading, data == nil { return false }
        return true
    }

    static func shouldClearRefreshError(
        cachedKey: String?,
        groupId: String,
        viewerId: String?
    ) -> Bool {
        guard let cachedKey else { return false }
        return cachedKey != cacheKey(groupId: groupId, viewerId: viewerId)
    }
}

@MainActor
@Observable
final class SeasonLedgerLoader {
    private(set) var data: SeasonLedgerSeasonData?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var cachedKey: String?

    var showsRefreshFailureBanner: Bool {
        SeasonLedgerRefreshPresentation.showsRefreshFailureBanner(
            errorMessage: errorMessage,
            data: data
        )
    }

    var showsFullLoadError: Bool {
        SeasonLedgerRefreshPresentation.showsFullLoadError(
            errorMessage: errorMessage,
            data: data,
            isLoading: isLoading
        )
    }

    func clearRefreshErrorIfIdentityChanged(groupId: String, viewerId: String?) {
        if SeasonLedgerRefreshPresentation.shouldClearRefreshError(
            cachedKey: cachedKey,
            groupId: groupId,
            viewerId: viewerId
        ) {
            errorMessage = nil
        }
    }

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
            cachedKey = nil
            return
        }
        let key = SeasonLedgerRefreshPresentation.cacheKey(
            groupId: group.id,
            viewerId: appState.currentUserId
        )
        clearRefreshErrorIfIdentityChanged(groupId: group.id, viewerId: appState.currentUserId)
        if !forceRefresh, cachedKey == key, let data {
            self.data = data
            return
        }
        if !forceRefresh, let cached = Self.seasonCache[key] {
            data = cached
            cachedKey = key
            return
        }
        await reload(appState: appState)
    }

    func reload(appState: AppState) async {
        guard let group = appState.groupService.selectedGroup else {
            data = nil
            cachedKey = nil
            return
        }
        let key = SeasonLedgerRefreshPresentation.cacheKey(
            groupId: group.id,
            viewerId: appState.currentUserId
        )
        let hadData = data != nil
        isLoading = true
        if !hadData {
            errorMessage = nil
        }
        defer { isLoading = false }
        do {
            let built = try await Self.buildSeason(
                groupId: group.id,
                seasonYear: Self.resolveSeasonYear(groupService: appState.groupService),
                leaguePickMode: group.rules.pickMode,
                members: appState.groupService.members,
                viewerId: appState.currentUserId,
                pickService: appState.pickService,
                groupService: appState.groupService
            )
            data = built
            cachedKey = key
            errorMessage = nil
            Self.seasonCache[key] = built
        } catch {
            errorMessage = UserFacingError.message(for: error, context: .generic)
                ?? error.localizedDescription
            if cachedKey != key {
                data = nil
            }
        }
    }

    static func clearAllCache() {
        seasonCache.removeAll()
    }

    static func invalidate(groupId: String) {
        let prefix = "\(groupId)|"
        for key in seasonCache.keys where key.hasPrefix(prefix) {
            seasonCache.removeValue(forKey: key)
        }
    }

    private static func resolveSeasonYear(groupService: GroupService) -> Int {
        groupService.currentWeek?.seasonYear
            ?? groupService.cfbWeek?.seasonYear
            ?? CFBSeasonCalendar.seasonYear()
    }

    private static func buildSeason(
        groupId: String,
        seasonYear: Int,
        leaguePickMode: PickMode,
        members: [GroupMember],
        viewerId: String?,
        pickService: PickService,
        groupService: GroupService
    ) async throws -> SeasonLedgerSeasonData {
        let fetched = try await groupService.fetchPastWeeks(groupId: groupId, limit: Self.weekFetchLimit)
        let eligible = SeasonLedgerWeekEligibility.eligibleWeeks(
            from: fetched,
            seasonYear: seasonYear
        )

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
                var map = Dictionary(picks.map { ($0.userId, $0) }, uniquingKeysWith: { _, new in new })
                map[own.userId] = own
                picks = Array(map.values)
            }
        }

        let pickMode = resolvedWeek.resolvedPickMode(leagueMode: leaguePickMode)
        let hidden = SeasonLedgerPrivacy.hiddenGameIds(week: resolvedWeek, games: games)
        let picksByUserId = Dictionary(picks.map { ($0.userId, $0) }, uniquingKeysWith: { _, new in new })

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