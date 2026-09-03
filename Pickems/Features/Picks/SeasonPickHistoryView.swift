import SwiftUI

struct SeasonPickHistoryView: View {
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

    private var selectedWeek: WeekSummary? {
        weeks.first { $0.id == selectedWeekId } ?? boardWeek
    }

    private var isViewingLiveWeek: Bool {
        selectedWeekId == appState.groupService.currentWeek?.id
    }

    private var displayGames: [SlateGame] {
        if isViewingLiveWeek, !appState.pickService.slateGames.isEmpty {
            return appState.pickService.slateGames.sortedByKickoff
        }
        return boardGames
    }

    private var picksByUserId: [String: UserPick] {
        var merged = boardPicks
        if isViewingLiveWeek {
            merged = PickService.mergingRevealedPicks(
                base: appState.pickService.allPicks.isEmpty ? merged : appState.pickService.allPicks,
                revealed: appState.pickService.revealedPicksByGameId,
                members: appState.groupService.members
            )
        }
        var map = Dictionary(uniqueKeysWithValues: merged.map { ($0.userId, $0) })
        if isViewingLiveWeek, let own = appState.pickService.userPick {
            map[own.userId] = own
        }
        return map
    }

    private func hiddenGameIds(for week: WeekSummary) -> Set<String> {
        guard week.isRollingLock, !WeekTransition.pickemsAreFullyPublic(week) else { return [] }
        return Set(
            displayGames
                .filter { !WeekTransition.isGameLocked($0, week: week) }
                .map(\.id)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoadingWeeks {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .accessibilityLabel("Loading season history")
                } else if weeks.isEmpty, let error = loadError {
                    ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                } else if weeks.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Past weeks appear here after Pickems lock.")
                    )
                } else {
                    weekSelector
                    boardSection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Season History")
        .navigationBarTitleDisplayMode(.large)
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpInfoButton(topic: PickemsHelp.seasonHistory, size: .body)
            }
        }
        .task {
            await loadWeeks()
        }
        .task(id: selectedWeekId) {
            await loadBoard()
        }
    }

    private var weekSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weeks) { week in
                        weekChip(week)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func weekChip(_ week: WeekSummary) -> some View {
        let isSelected = week.id == selectedWeekId
        return Button {
            PickemsHaptics.selection()
            selectedWeekId = week.id
        } label: {
            VStack(spacing: 2) {
                Text("Week \(week.weekNumber)")
                    .font(.subheadline.weight(.semibold))
                if let range = appState.groupService.dateRangeLabel(for: week.id), !range.isEmpty {
                    Text(range)
                        .font(.caption2.weight(.medium))
                        .opacity(isSelected ? 0.9 : 0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? theme.accent : PickemsColors.cardBackground)
            .foregroundStyle(isSelected ? theme.onAccent : PickemsColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(week.weekNumber)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Show this week's league Pickems")
    }

    @ViewBuilder
    private var boardSection: some View {
        if isLoadingBoard {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityLabel("Loading league Pickems")
        } else if let error = loadError {
            ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
        } else if let week = selectedWeek {
            if WeekTransition.pickemsShouldShowLeagueBoard(week), !displayGames.isEmpty {
                if let caption = yourRecordCaption {
                    Text(caption)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PickemsColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .accessibilityLabel(caption)
                }
                LeaguePickemsBoard(
                    members: appState.groupService.members,
                    games: displayGames,
                    picksByUserId: picksByUserId,
                    liveCards: isViewingLiveWeek ? appState.picksViewModel.livePickCards : [:],
                    teamRanks: appState.picksViewModel.teamRanks,
                    currentUserId: appState.currentUserId,
                    hiddenGameIds: hiddenGameIds(for: week)
                )
                .padding(.horizontal)
            } else if WeekTransition.pickemsShouldShowLeagueBoard(week) {
                EmptyStateView(
                    icon: "american.football.fill",
                    title: "No slate games",
                    message: "This week locked without games on the slate.",
                    help: PickemsHelp.seasonHistory
                )
            } else if let next = PickDeadlineCalculator.nextLockDate(week: week, games: displayGames) {
                PickDeadlineBanner(
                    deadline: next,
                    isRolling: week.isRollingLock,
                    openCount: PickDeadlineCalculator.openGameCount(week: week, games: displayGames),
                    totalCount: displayGames.count
                )
                Text(week.isRollingLock
                    ? "Locked games show on the chart. Later picks stay hidden until kickoff."
                    : "League Pickems show here after lock.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                EmptyStateView(
                    icon: "lock.open",
                    title: "Pickems aren't public yet",
                    message: "This week's chart opens after Pickems lock.",
                    help: PickemsHelp.seasonHistory
                )
            }
        }
    }

    private var yourRecordCaption: String? {
        guard let userId = appState.currentUserId,
              let pick = picksByUserId[userId] else { return nil }
        let record = ScoringEngine.scorePicks(picks: pick.picks, games: displayGames)
        return "You went \(record.wins)–\(record.losses)"
    }

    private func loadWeeks() async {
        isLoadingWeeks = true
        defer { isLoadingWeeks = false }
        guard let group = appState.groupService.selectedGroup else {
            weeks = []
            return
        }
        do {
            let fetched = try await appState.groupService.fetchPastWeeks(groupId: group.id)
            weeks = fetched
                .filter { $0.status == .scored || $0.status == .locked }
                .sorted { $0.weekNumber > $1.weekNumber }
            loadError = nil
            if selectedWeekId == nil {
                selectedWeekId = weeks.first?.id
            }
        } catch {
            weeks = []
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
