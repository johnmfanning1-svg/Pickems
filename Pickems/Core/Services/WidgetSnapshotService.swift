import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    /// Large Home Screen widgets can show ~13 names; keep a couple extra for bigger families.
    static let maxListedEntries = 15

    private static var fetchGeneration = 0

    /// Immediate reloads follow a save or a week change. Score ticks stay inside the widget refresh budget.
    enum TimelineReload {
        case immediate
        case budgeted
    }

    private static var rememberedLiveScores: [String: WidgetSnapshotBuilder.LiveScore] = [:]
    private static var lastBudgetedReload = Date.distantPast
    private static let budgetedReloadInterval: TimeInterval = 15 * 60

    static func publish(from appState: AppState, timelineReload: TimelineReload = .immediate) {
        WidgetDisplayFollowMigration.applyIfPossible(
            selectedGroupId: appState.groupService.selectedGroup?.id
        )
        PickemsAppGroup.saveLeagues(
            appState.groupService.groups.map { WidgetLeague(id: $0.id, name: $0.name) }
        )
        dropStaleDisplayPreference(from: appState)
        clearSnapshotIfMembershipLost(from: appState)

        guard let group = resolvedDisplayGroup(from: appState) else {
            PickemsAppGroup.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        if CFBSeasonCalendar.isPreseason() {
            publishPreseason(from: appState, group: group, timelineReload: timelineReload)
            return
        }
        publishStandings(from: appState, group: group, timelineReload: timelineReload)
    }

    /// Home and Pickems already have these cards. Later publishes reuse them for the snapshot.
    static func rememberLiveCards(_ cards: [ESPNLiveGameCard]) {
        for card in cards {
            let text = ESPNLiveGameCard.strippingTrailingScore(from: card.statusDetail)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let score = WidgetSnapshotBuilder.LiveScore(
                awayScore: card.awayScore,
                homeScore: card.homeScore,
                status: card.status,
                statusText: text.isEmpty ? nil : text
            )
            if !card.espnEventId.isEmpty {
                rememberedLiveScores[card.espnEventId] = score
            }
            if !card.id.isEmpty, card.id != card.espnEventId {
                rememberedLiveScores[card.id] = score
            }
        }
    }

    /// League the widget and Live Activities should show.
    static func resolvedDisplayGroup(from appState: AppState) -> PickemGroup? {
        let ids = appState.groupService.groups.map(\.id)
        guard let id = WidgetDisplayGroupResolver.resolve(
            savedId: PickemsAppGroup.displayGroupId(),
            selectedGroupId: appState.groupService.selectedGroup?.id,
            groupIds: ids
        ) else { return nil }
        return appState.groupService.groups.first { $0.id == id }
    }

    static func dropStaleDisplayPreference(from appState: AppState) {
        let ids = appState.groupService.groups.map(\.id)
        guard let saved = PickemsAppGroup.displayGroupId(), !ids.contains(saved) else { return }
        PickemsAppGroup.setDisplayGroupId(nil)
    }

    private static func clearSnapshotIfMembershipLost(from appState: AppState) {
        let memberIds = Set(appState.groupService.groups.map(\.id))
        guard let snapshot = PickemsAppGroup.load(), !memberIds.contains(snapshot.groupId) else { return }
        PickemsAppGroup.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func publishPreseason(
        from appState: AppState,
        group: PickemGroup,
        timelineReload: TimelineReload
    ) {
        let kickoff = CFBSeasonCalendar.nextSeasonKickoff()
        let seasonYear = CFBSeasonCalendar.seasonYear(containing: kickoff)
        let user = appState.authService.currentUser

        // Align with Pickems week numbering (Week 0 is a real slate in 2026).
        let espnWeek = appState.groupService.cfbWeek
        let weekNumber: Int
        if let current = appState.groupService.currentWeek?.weekNumber {
            weekNumber = current
        } else if let espnWeek {
            weekNumber = CFBWeekCalendar.resolve(espn: espnWeek).weekNumber
        } else {
            weekNumber = CFBWeekCalendar.resolve(
                espn: CFBWeekInfo(
                    seasonYear: seasonYear,
                    weekNumber: CFBWeekSync.estimatedCFBWeek(),
                    seasonType: 2,
                    label: ""
                )
            ).weekNumber
        }
        let snapshot = StandingsSnapshot(
            groupId: group.id,
            groupName: group.name,
            weekNumber: weekNumber,
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
        reloadTimelines(timelineReload)
    }

    private static func publishStandings(
        from appState: AppState,
        group: PickemGroup,
        timelineReload: TimelineReload
    ) {
        guard let user = appState.authService.currentUser else {
            PickemsAppGroup.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        if group.id == appState.groupService.selectedGroup?.id,
           let ranked = selectedGroupRankedStandings(from: appState, group: group) {
            let week = appState.groupService.currentWeek
            let weekNumber = standingsWeekNumber(
                from: appState,
                standings: appState.groupService.standings,
                week: week
            )
            saveStandingsSnapshot(
                group: group,
                userId: user.id,
                userDisplayName: user.displayName,
                weekNumber: weekNumber,
                seasonYear: standingsSeasonYear(from: appState, week: week),
                ranked: ranked,
                extras: extras(from: appState, group: group, week: week, weekNumber: weekNumber),
                timelineReload: timelineReload
            )
            return
        }

        // This league's board is not loaded. Keep a snapshot that already belongs
        // to it. Follow still has the previous league's snapshot, so fetch below
        // and reload as soon as that league's standings come back.
        if group.id == appState.groupService.selectedGroup?.id,
           !WidgetDisplayGroupResolver.shouldFetchStandingsWhenBoardMissing(
               displayGroupId: group.id,
               snapshotGroupId: PickemsAppGroup.load()?.groupId
           ) {
            return
        }

        fetchGeneration += 1
        let generation = fetchGeneration
        let groupId = group.id
        let userId = user.id
        let displayName = user.displayName
        Task {
            await publishStandingsFromFetch(
                appState: appState,
                groupId: groupId,
                userId: userId,
                userDisplayName: displayName,
                generation: generation,
                timelineReload: timelineReload
            )
        }
    }

    private static func publishStandingsFromFetch(
        appState: AppState,
        groupId: String,
        userId: String,
        userDisplayName: String,
        generation: Int,
        timelineReload: TimelineReload
    ) async {
        let fetched = await appState.groupService.fetchStandings(groupId: groupId)
        guard generation == fetchGeneration else { return }
        guard let group = resolvedDisplayGroup(from: appState), group.id == groupId else { return }
        // The open league's board landed while this fetch was in flight.
        if group.id == appState.groupService.selectedGroup?.id,
           selectedGroupRankedStandings(from: appState, group: group) != nil {
            return
        }

        let ranked = rankedDisplayEntries(
            standings: fetched.standings,
            members: fetched.members,
            memberIds: group.memberIds,
            tieBreaker: group.rules.tieBreaker,
            tieBreakOrder: fetched.week?.tieBreakOrder ?? [],
            displayedWeekNumber: fetched.week?.weekNumber
        )
        let weekNumber = standingsWeekNumber(from: appState, standings: fetched.standings, week: fetched.week)
        let pickMode = fetched.week?.resolvedPickMode(leagueMode: group.rules.pickMode) ?? group.rules.pickMode
        let fresh = WidgetSnapshotBuilder.extras(
            week: fetched.week,
            games: [],
            picks: [:],
            pickMode: pickMode
        )
        saveStandingsSnapshot(
            group: group,
            userId: userId,
            userDisplayName: userDisplayName,
            weekNumber: weekNumber,
            seasonYear: standingsSeasonYear(from: appState, week: fetched.week),
            ranked: ranked,
            extras: WidgetSnapshotBuilder.carryForward(
                fresh,
                previous: PickemsAppGroup.load(),
                groupId: group.id,
                weekNumber: weekNumber
            ),
            timelineReload: timelineReload
        )
    }

    /// Selected-league snapshot. Nil when this league's roster/standings are not loaded yet —
    /// keep the last good App Group payload instead of mixing in another league's members.
    static func selectedGroupRankedStandings(
        from appState: AppState,
        group: PickemGroup
    ) -> [StandingEntry]? {
        if appState.groupService.membersGroupId == group.id {
            return appState.rankedStandings(weekly: true)
        }
        guard appState.groupService.standings != nil else { return nil }
        return rankedDisplayEntries(
            standings: appState.groupService.standings,
            members: [],
            memberIds: group.memberIds,
            tieBreaker: group.rules.tieBreaker,
            tieBreakOrder: appState.groupService.currentWeek?.tieBreakOrder ?? [],
            displayedWeekNumber: appState.groupService.currentWeek?.weekNumber
        )
    }

    static func rankedDisplayEntries(
        standings: GroupStandings?,
        members: [GroupMember],
        memberIds: [String] = [],
        tieBreaker: TieBreakerPolicy,
        tieBreakOrder: [String] = [],
        displayedWeekNumber: Int? = nil
    ) -> [StandingEntry] {
        let base = StandingBoard.baseEntries(
            standingsEntries: standings?.entries,
            members: members,
            memberIds: memberIds,
            standingsWeekNumber: standings?.weekNumber,
            displayedWeekNumber: displayedWeekNumber
        )
        guard !base.isEmpty else { return [] }
        return ScoringEngine.rankedStandings(
            entries: base,
            weekly: true,
            tieBreaker: tieBreaker,
            tieBreakOrder: tieBreakOrder
        )
    }

    /// Games already on screen for this league and week. No extra Firestore read.
    /// When that listener is on another league or week, keep the previous slate.
    private static func extras(
        from appState: AppState,
        group: PickemGroup,
        week: WeekSummary?,
        weekNumber: Int
    ) -> WidgetSnapshotBuilder.Extras {
        let pickMode = week?.resolvedPickMode(leagueMode: group.rules.pickMode) ?? group.rules.pickMode
        if let slate = loadedSlate(from: appState, group: group, week: week) {
            let scores = liveScores(from: appState)
            return WidgetSnapshotBuilder.extras(
                week: week,
                games: slate.games,
                picks: slate.picks,
                pickMode: pickMode,
                statusTextByGameId: statusTextByGameId(from: appState, games: slate.games),
                nominations: appState.pickService.nominations,
                userId: appState.authService.currentUser?.id ?? "",
                liveScores: scores,
                nominationsLoaded: appState.pickService.didLoadNominations,
                memberQuota: CommissionerPinnedLeague.selectionsPerMember(
                    weekValue: week?.selectionsPerMember ?? 0,
                    pinnedRulesValue: group.rules.selectionsPerMember
                ),
                slateQuota: max((week?.slateSize ?? 0) > 0 ? week?.slateSize ?? 0 : group.rules.slateSize, 1),
                memberIds: group.memberIds,
                rulesSelectionsPerMember: group.rules.selectionsPerMember,
                slateEventIds: appState.pickService.didLoadSlateGames
                    ? appState.pickService.slateGames.map(\.espnEventId)
                    : nil,
                gamesTarget: group.rules.expectedSlateSize(memberCount: max(group.memberIds.count, 1))
            )
        }
        let fresh = WidgetSnapshotBuilder.extras(week: week, games: [], picks: [:], pickMode: pickMode)
        return WidgetSnapshotBuilder.carryForward(
            fresh,
            previous: PickemsAppGroup.load(),
            groupId: group.id,
            weekNumber: weekNumber
        )
    }

    /// Nil when this league's slate for this week is not the one on screen.
    private static func loadedSlate(
        from appState: AppState,
        group: PickemGroup,
        week: WeekSummary?
    ) -> (games: [SlateGame], picks: [String: String])? {
        guard let week,
              appState.pickService.observingGroupId == group.id,
              appState.pickService.observedWeekId == week.id else {
            return nil
        }
        let official = appState.pickService.slateGames
        // During Selections the slate is the merged nominations. After lock, keep that
        // merge until the games collection has the final slate, so a status flip cannot
        // publish an empty board.
        let games = (week.status == .selection || official.isEmpty)
            ? appState.pickService.displaySlateGames
            : official
        return (games, appState.pickService.userPick?.picks ?? [:])
    }

    private static func liveScores(from appState: AppState) -> [String: WidgetSnapshotBuilder.LiveScore] {
        var scores = rememberedLiveScores
        for card in appState.picksViewModel.livePickCards.values {
            let key = card.espnEventId.isEmpty ? card.id : card.espnEventId
            guard !key.isEmpty, scores[key] == nil else { continue }
            let text = ESPNLiveGameCard.strippingTrailingScore(from: card.statusDetail)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let score = WidgetSnapshotBuilder.LiveScore(
                awayScore: card.awayScore,
                homeScore: card.homeScore,
                status: card.status,
                statusText: text.isEmpty ? nil : text
            )
            scores[key] = score
            if !card.id.isEmpty, card.id != key {
                scores[card.id] = score
            }
        }
        return scores
    }

    /// Clock lines already on screen. No extra network read from the widget path.
    private static func statusTextByGameId(from appState: AppState, games: [SlateGame]) -> [String: String] {
        let cards = appState.picksViewModel.livePickCards
        var map: [String: String] = [:]
        for game in games {
            let card = cards[game.id] ?? cards[game.espnEventId]
            guard let card else { continue }
            let clock = ESPNLiveGameCard.strippingTrailingScore(from: card.statusDetail)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clock.isEmpty {
                map[game.id] = clock
            }
        }
        for (id, score) in rememberedLiveScores {
            guard let text = score.statusText, !text.isEmpty else { continue }
            map[id] = text
        }
        return map
    }

    private static func saveStandingsSnapshot(
        group: PickemGroup,
        userId: String,
        userDisplayName: String,
        weekNumber: Int,
        seasonYear: Int,
        ranked: [StandingEntry],
        extras: WidgetSnapshotBuilder.Extras = .empty,
        timelineReload: TimelineReload = .immediate
    ) {
        let mine = ranked.first(where: { $0.id == userId })
        let rank = mine?.rank ?? 0
        let prior = PickemsAppGroup.load()
        let snapshot = StandingsSnapshot(
            groupId: group.id,
            groupName: group.name,
            weekNumber: weekNumber,
            seasonYear: seasonYear,
            userId: userId,
            userDisplayName: userDisplayName,
            weeklyWins: mine?.weeklyWins ?? 0,
            weeklyLosses: mine?.weeklyLosses ?? 0,
            seasonWins: mine?.seasonWins ?? 0,
            seasonLosses: mine?.seasonLosses ?? 0,
            rank: rank,
            totalPlayers: ranked.count,
            topEntries: ranked.prefix(Self.maxListedEntries).map {
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
            seasonKickoffAt: nil,
            selectionsDeadline: extras.selectionsDeadline,
            pickemsDeadline: extras.pickemsDeadline,
            rollingLock: extras.rollingLock,
            games: extras.games,
            nextLockAt: extras.nextLockAt,
            weekPhaseHint: nil,
            picksMade: extras.picksMade,
            picksTotal: extras.picksTotal,
            selectionsMade: extras.selectionsMade,
            selectionsTotal: extras.selectionsTotal,
            selectionQuota: extras.selectionQuota,
            selectionMembersDone: extras.selectionMembersDone,
            selectionMembersTotal: extras.selectionMembersTotal,
            selectionGamesFilled: extras.selectionGamesFilled,
            selectionGamesTarget: extras.selectionGamesTarget,
            previousRank: WidgetSnapshotBuilder.previousRank(
                currentRank: rank,
                previous: prior,
                groupId: group.id,
                weekNumber: weekNumber
            )
        )
        PickemsAppGroup.save(snapshot)
        reloadTimelines(timelineReload)
    }

    private static func reloadTimelines(_ policy: TimelineReload) {
        switch policy {
        case .immediate:
            lastBudgetedReload = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: "PickemsStandingsWidget")
            WidgetCenter.shared.reloadAllTimelines()
        case .budgeted:
            let now = Date()
            guard now.timeIntervalSince(lastBudgetedReload) >= budgetedReloadInterval else { return }
            lastBudgetedReload = now
            WidgetCenter.shared.reloadTimelines(ofKind: "PickemsStandingsWidget")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func standingsWeekNumber(
        from appState: AppState,
        standings: GroupStandings?,
        week: WeekSummary?
    ) -> Int {
        // Prefer the displayed week: stale last-week tallies are zeroed against it.
        if let weekNumber = week?.weekNumber { return weekNumber }
        if let weekNumber = standings?.weekNumber { return weekNumber }
        if let current = appState.groupService.currentWeek?.weekNumber { return current }
        if let espn = appState.groupService.cfbWeek {
            return CFBWeekCalendar.resolve(espn: espn).weekNumber
        }
        return CFBWeekSync.estimatedCFBWeek()
    }

    private static func standingsSeasonYear(from appState: AppState, week: WeekSummary?) -> Int {
        week?.seasonYear
            ?? appState.groupService.currentWeek?.seasonYear
            ?? appState.groupService.cfbWeek?.seasonYear
            ?? Calendar.current.component(.year, from: Date())
    }
}
