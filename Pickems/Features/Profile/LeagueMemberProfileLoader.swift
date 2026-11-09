import Foundation

/// Reads scored and locked weeks the member can already see. Open pick sheets are never requested.
@MainActor
enum LeagueMemberProfileLoader {
    static func load(
        userId: String,
        viewerId: String?,
        groupId: String,
        leaguePickMode: PickMode,
        groupService: GroupService,
        pickService: PickService
    ) async -> LeagueMemberProfilePolicy.Snapshot {
        let weeks: [WeekSummary]
        do {
            var fetched = try await groupService.fetchPastWeeks(
                groupId: groupId,
                limit: LeagueMemberProfilePolicy.weekReadLimit
            )
            if let current = groupService.currentWeek,
               groupService.selectedGroup?.id == groupId,
               !fetched.contains(where: { $0.id == current.id }) {
                fetched.append(current)
            }
            weeks = fetched.filter { $0.status == .locked || $0.status == .scored }
        } catch {
            var failed = LeagueMemberProfilePolicy.Snapshot.empty
            failed.failed = true
            return failed
        }

        var memberWeeks: [LeagueMemberProfilePolicy.WeekInput] = []
        var viewerWeeks: [LeagueMemberProfilePolicy.WeekInput] = []
        let compareViewer = viewerId.flatMap { $0 == userId ? nil : $0 }

        for week in weeks {
            let memberHistory = try? await pickService.loadWeekHistory(
                groupId: groupId,
                weekId: week.id,
                userId: userId
            )
            let games = memberHistory?.slateGames ?? []
            let mode = week.resolvedPickMode(leagueMode: leaguePickMode)
            memberWeeks.append(
                input(
                    week: week,
                    pickMode: mode,
                    pick: memberHistory?.userPick,
                    games: games
                )
            )
            if let compareViewer {
                let viewerHistory = try? await pickService.loadWeekHistory(
                    groupId: groupId,
                    weekId: week.id,
                    userId: compareViewer
                )
                viewerWeeks.append(
                    input(
                        week: week,
                        pickMode: mode,
                        pick: viewerHistory?.userPick,
                        games: games
                    )
                )
            }
        }

        return LeagueMemberProfilePolicy.makeSnapshot(
            memberWeeks: memberWeeks,
            viewerWeeks: viewerWeeks
        )
    }

    /// Drops sheets the policy would refuse, so the profile never retains an open pick map.
    private static func input(
        week: WeekSummary,
        pickMode: PickMode,
        pick: UserPick?,
        games: [SlateGame]
    ) -> LeagueMemberProfilePolicy.WeekInput {
        let sheet = pick.map {
            LeagueMemberProfilePolicy.PickSheet(
                isLocked: $0.isLocked,
                picks: $0.picks,
                confidenceGameId: $0.confidenceGameId
            )
        }
        let visible = LeagueMemberProfilePolicy.canSummarize(status: week.status, pick: sheet) ? sheet : nil
        return LeagueMemberProfilePolicy.WeekInput(
            weekId: week.id,
            seasonYear: week.seasonYear,
            weekNumber: week.weekNumber,
            status: week.status,
            pickMode: pickMode,
            pick: visible,
            games: games
        )
    }
}
