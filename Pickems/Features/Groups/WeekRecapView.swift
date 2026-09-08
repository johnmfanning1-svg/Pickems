import SwiftUI

struct WeekRecapView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    @State private var weeks: [WeekSummary] = []
    @State private var selectedWeekId: String?
    @State private var boardWeek: WeekSummary?
    @State private var boardGames: [SlateGame] = []
    @State private var boardPicks: [UserPick] = []
    @State private var isLoadingWeeks = true
    @State private var isLoadingBoard = false
    @State private var loadError: String?

    private var liveWeekId: String? {
        appState.groupService.currentWeek?.id
    }

    private var selectedWeek: WeekSummary? {
        if let selectedWeekId, let match = weeks.first(where: { $0.id == selectedWeekId }) {
            return match
        }
        if isViewingLiveWeek {
            return appState.groupService.currentWeek ?? boardWeek
        }
        return boardWeek
    }

    private var isViewingLiveWeek: Bool {
        selectedWeekId == liveWeekId
    }

    private var displayGames: [SlateGame] {
        if isViewingLiveWeek, !appState.pickService.slateGames.isEmpty {
            return appState.pickService.slateGames.sortedByKickoff
        }
        return boardGames
    }

    private var displayPicks: [UserPick] {
        var merged = boardPicks
        if isViewingLiveWeek {
            merged = PickService.mergingRevealedPicks(
                base: appState.pickService.allPicks.isEmpty ? merged : appState.pickService.allPicks,
                revealed: appState.pickService.revealedPicksByGameId,
                members: appState.groupService.members
            )
            if let own = appState.pickService.userPick {
                merged.removeAll { $0.userId == own.userId }
                merged.append(own)
            }
        }
        return merged
    }

    private func hiddenGameIds(for week: WeekSummary) -> Set<String> {
        guard week.isRollingLock, !WeekTransition.pickemsAreFullyPublic(week) else { return [] }
        return Set(
            displayGames
                .filter { !WeekTransition.isGameLocked($0, week: week) }
                .map(\.id)
        )
    }

    private var scoringGames: [SlateGame] {
        guard let week = selectedWeek else { return displayGames }
        let hidden = hiddenGameIds(for: week)
        return displayGames.filter { !hidden.contains($0.id) }
    }

    private var rankedEntries: [StandingEntry] {
        appState.weeklyRankedStandings(fromPicks: displayPicks, games: scoringGames)
    }

    private var recapText: String {
        guard let week = selectedWeek, let group = appState.groupService.selectedGroup else {
            return "Pick a week to see the recap."
        }
        return WeekRecapGenerator.recap(
            groupName: group.name,
            week: week,
            entries: rankedEntries,
            userId: appState.authService.currentUser?.id
        )
    }

    private var awards: WeekAwards? {
        if let stored = selectedWeek?.awards, hasAnyAward(stored) {
            return stored
        }
        guard scoringGames.contains(where: { $0.status == .final }) else { return nil }
        let computed = WeekAwardsEngine.compute(
            picks: displayPicks,
            games: scoringGames,
            members: appState.groupService.members
        )
        let awards = WeekAwards(
            sharpshooterUserId: computed.sharpshooterUserId,
            heartbreakerUserId: computed.heartbreakerUserId,
            contrarianUserId: computed.contrarianUserId
        )
        return hasAnyAward(awards) ? awards : nil
    }

    private var shareSource: ShareSource? {
        guard let week = selectedWeek else { return nil }
        return appState.weeklyShareSource(week: week, ranked: rankedEntries)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                weekSelector

                if let error = loadError, weeks.isEmpty {
                    ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                        .padding(.horizontal)
                } else if isLoadingBoard {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .accessibilityLabel("Loading week recap")
                } else if let error = loadError {
                    ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                        .padding(.horizontal)
                } else if selectedWeek != nil {
                    recapContent
                }
            }
            .padding(.vertical)
        }
        .pickemsScreenBackground()
        .navigationTitle("Week Recap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            HelpToolbarItem(topic: PickemsHelp.weekRecap)
        }
        .task {
            await loadWeeks()
        }
        .task(id: selectedWeekId) {
            await loadBoard()
        }
    }

    @ViewBuilder
    private var weekSelector: some View {
        if isLoadingWeeks {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityLabel("Loading weeks")
        } else if weeks.isEmpty {
            Text("No weeks yet")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
                .padding(.horizontal)
        } else {
            WeekChipBar(
                weeks: weeks,
                selectedWeekId: selectedWeekId,
                activeWeekId: liveWeekId,
                dateRangeLabel: { appState.groupService.dateRangeLabel(for: $0.id) },
                accessibilityHint: "Show this week's recap"
            ) { week in
                PickemsHaptics.selection()
                selectedWeekId = week.id
            }
        }
    }

    private var recapContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            WeekRecapCard(recapText: recapText)

            if let awards {
                WeekAwardsBanner(awards: awards)
                    .padding(.horizontal)
            }

            if let shareSource {
                ShareResultsButton(source: shareSource)
                    .padding(.horizontal)
            } else if selectedWeek?.status != .scored {
                Text("Share Results shows up once you have a scored Pickem this week.")
                    .font(.footnote)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .padding(.horizontal)
            }
        }
    }

    private func hasAnyAward(_ awards: WeekAwards) -> Bool {
        awards.sharpshooterUserId != nil
            || awards.heartbreakerUserId != nil
            || awards.contrarianUserId != nil
    }

    private func loadWeeks() async {
        isLoadingWeeks = true
        defer { isLoadingWeeks = false }
        guard let group = appState.groupService.selectedGroup else {
            weeks = []
            return
        }
        do {
            await appState.groupService.loadAvailableWeeks(groupId: group.id)
            var fetched = try await appState.groupService.fetchPastWeeks(groupId: group.id)
            if let current = appState.groupService.currentWeek,
               !fetched.contains(where: { $0.id == current.id }) {
                fetched.append(current)
            }
            weeks = LeaguePickemsComparisonCopy.orderedWeeks(fetched)
            loadError = nil
            if selectedWeekId == nil {
                selectedWeekId = liveWeekId ?? weeks.last?.id
            }
        } catch {
            if let current = appState.groupService.currentWeek {
                weeks = [current]
                selectedWeekId = current.id
            } else {
                weeks = []
            }
            loadError = UserFacingError.message(for: error, context: .generic)
                ?? error.localizedDescription
        }
    }

    private func loadBoard() async {
        guard let group = appState.groupService.selectedGroup,
              let weekId = selectedWeekId else { return }
        isLoadingBoard = true
        defer { isLoadingBoard = false }
        do {
            let snapshot = try await appState.pickService.fetchLeagueBoard(
                groupId: group.id,
                weekId: weekId
            )
            guard selectedWeekId == weekId else { return }
            boardWeek = snapshot.week
            boardGames = snapshot.games
            boardPicks = snapshot.picks
            if let idx = weeks.firstIndex(where: { $0.id == weekId }) {
                weeks[idx] = snapshot.week
            }
            loadError = nil
        } catch {
            guard selectedWeekId == weekId else { return }
            boardWeek = nil
            boardGames = []
            boardPicks = []
            loadError = UserFacingError.message(for: error, context: .generic)
                ?? error.localizedDescription
        }
    }
}
