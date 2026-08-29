import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    /// Large Home Screen widgets can show ~10 names; keep a couple extra for bigger families.
    static let maxListedEntries = 12

    private static var fetchGeneration = 0

    static func publish(from appState: AppState) {
        dropStaleDisplayPreference(from: appState)
        clearSnapshotIfMembershipLost(from: appState)

        guard let group = resolvedDisplayGroup(from: appState) else {
            PickemsAppGroup.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        if CFBSeasonCalendar.isPreseason() {
            publishPreseason(from: appState, group: group)
            return
        }
        publishStandings(from: appState, group: group)
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

    private static func publishPreseason(from appState: AppState, group: PickemGroup) {
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
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func publishStandings(from appState: AppState, group: PickemGroup) {
        guard let user = appState.authService.currentUser else {
            PickemsAppGroup.clear()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        if group.id == appState.groupService.selectedGroup?.id {
            let ranked = appState.rankedStandings(weekly: true)
            saveStandingsSnapshot(
                group: group,
                userId: user.id,
                userDisplayName: user.displayName,
                weekNumber: standingsWeekNumber(from: appState, standings: appState.groupService.standings, week: appState.groupService.currentWeek),
                seasonYear: standingsSeasonYear(from: appState, week: appState.groupService.currentWeek),
                ranked: ranked
            )
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
                generation: generation
            )
        }
    }

    private static func publishStandingsFromFetch(
        appState: AppState,
        groupId: String,
        userId: String,
        userDisplayName: String,
        generation: Int
    ) async {
        let fetched = await appState.groupService.fetchStandings(groupId: groupId)
        guard generation == fetchGeneration else { return }
        guard let group = resolvedDisplayGroup(from: appState), group.id == groupId else { return }

        let ranked = rankedDisplayEntries(
            standings: fetched.standings,
            members: fetched.members,
            tieBreaker: group.rules.tieBreaker
        )
        saveStandingsSnapshot(
            group: group,
            userId: userId,
            userDisplayName: userDisplayName,
            weekNumber: standingsWeekNumber(from: appState, standings: fetched.standings, week: fetched.week),
            seasonYear: standingsSeasonYear(from: appState, week: fetched.week),
            ranked: ranked
        )
    }

    static func rankedDisplayEntries(
        standings: GroupStandings?,
        members: [GroupMember],
        tieBreaker: TieBreakerPolicy
    ) -> [StandingEntry] {
        let base: [StandingEntry]
        if let entries = standings?.entries, !entries.isEmpty {
            base = entries
        } else if !members.isEmpty {
            base = members.map { member in
                StandingEntry(
                    id: member.id,
                    displayName: member.displayName,
                    avatarColorHex: member.avatarColorHex,
                    weeklyWins: 0,
                    weeklyLosses: 0,
                    seasonWins: member.seasonWins,
                    seasonLosses: member.seasonLosses,
                    rank: 0,
                    isTied: false,
                    joinedAt: member.joinedAt,
                    avatarImageURL: member.avatarImageURL
                )
            }
        } else {
            return []
        }
        return ScoringEngine.rankedStandings(entries: base, weekly: true, tieBreaker: tieBreaker)
    }

    private static func saveStandingsSnapshot(
        group: PickemGroup,
        userId: String,
        userDisplayName: String,
        weekNumber: Int,
        seasonYear: Int,
        ranked: [StandingEntry]
    ) {
        let mine = ranked.first(where: { $0.id == userId })
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
            rank: mine?.rank ?? 0,
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
            seasonKickoffAt: nil
        )
        PickemsAppGroup.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func standingsWeekNumber(
        from appState: AppState,
        standings: GroupStandings?,
        week: WeekSummary?
    ) -> Int {
        if let weekNumber = standings?.weekNumber { return weekNumber }
        if let weekNumber = week?.weekNumber { return weekNumber }
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
