import SwiftUI

/// Head-to-head league chart: Game | You | selected member.
struct LeaguePickemsComparisonView: View {
    let opponent: StandingEntry

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

    private var currentUserId: String? {
        appState.currentUserId
    }

    private var members: [GroupMember] {
        appState.groupService.members
    }

    private var picksByUserId: [String: UserPick] {
        var merged = boardPicks
        if isViewingLiveWeek {
            merged = PickService.mergingRevealedPicks(
                base: appState.pickService.allPicks.isEmpty ? merged : appState.pickService.allPicks,
                revealed: appState.pickService.revealedPicksByGameId,
                members: members
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

    private var opponentMember: GroupMember {
        if let member = members.first(where: { $0.id == opponent.id }) {
            return member
        }
        return Self.member(from: opponent)
    }

    private var youMember: GroupMember? {
        if let currentUserId, let member = members.first(where: { $0.id == currentUserId }) {
            return member
        }
        return nil
    }

    private var comparisonMembers: [GroupMember] {
        var result: [GroupMember] = []
        if let youMember {
            result.append(youMember)
        }
        result.append(opponentMember)
        return result
    }

    private var opponentShortName: String {
        let parts = opponent.displayName.split(separator: " ")
        if let first = parts.first { return String(first) }
        return opponent.displayName
    }

    private var showsBoard: Bool {
        guard let week = selectedWeek else { return false }
        return WeekTransition.pickemsShouldShowLeagueBoard(week)
    }

    private var isRollingMessage: Bool {
        guard let week = selectedWeek else {
            return appState.groupService.selectedGroup?.rules.pickDeadline == .rolling
        }
        if week.pickLockMode != nil { return week.isRollingLock }
        return appState.groupService.selectedGroup?.rules.pickDeadline == .rolling
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                weekSelector
                comparisonHeader
                    .padding(.horizontal)
                boardSection
            }
            .padding(.vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pickemsScreenBackground()
        .navigationTitle("You vs \(opponentShortName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            HelpToolbarItem(topic: PickemsHelp.leaguePickems)
        }
        .task {
            await loadWeeks()
        }
        .task(id: selectedWeekId) {
            await loadBoard()
        }
        .task(id: "\(appState.groupService.selectedGroup?.id ?? "")-\(liveWeekId ?? "")-\(showsBoard)") {
            guard isViewingLiveWeek, showsBoard else { return }
            await appState.picksViewModel.ensureTeamRanks(appState: appState)
            if let week = selectedWeek {
                appState.picksViewModel.startLiveRefresh(week: week, appState: appState)
            }
        }
    }

    private var weekSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

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
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(weeks) { week in
                                weekChip(week)
                                    .id(week.id)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onAppear { scrollToSelected(proxy) }
                    .onChange(of: selectedWeekId) { _, _ in scrollToSelected(proxy) }
                    .onChange(of: weeks.map(\.id)) { _, _ in scrollToSelected(proxy) }
                }
            }
        }
    }

    private func weekChip(_ week: WeekSummary) -> some View {
        let isSelected = week.id == selectedWeekId
        let isCurrent = week.id == liveWeekId
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
                if isCurrent {
                    Text("Current")
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
        .accessibilityHint(isCurrent ? "Current week" : "Show this week's comparison")
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy) {
        guard let selectedWeekId else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(selectedWeekId, anchor: UnitPoint.center)
            }
        }
    }

    @ViewBuilder
    private var boardSection: some View {
        if let error = loadError, weeks.isEmpty {
            ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                .padding(.horizontal)
        } else if let week = selectedWeek, !showsBoard {
            let copy = LeaguePickemsComparisonCopy.pendingBoard(
                isRolling: isRollingMessage,
                isSelection: week.status == .selection
            )
            pendingComparisonMessage(title: copy.title, message: copy.message)
                .padding(.horizontal)
        } else if isLoadingBoard {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityLabel("Loading league Pickems")
        } else if let error = loadError {
            ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                .padding(.horizontal)
        } else if showsBoard, displayGames.isEmpty {
            EmptyStateView(
                icon: "american.football.fill",
                title: "No slate games",
                message: "This week locked without games on the slate.",
                help: PickemsHelp.leaguePickems
            )
        } else if showsBoard, let week = selectedWeek {
            LeaguePickemsBoard(
                members: comparisonMembers,
                games: displayGames,
                picksByUserId: picksByUserId,
                liveCards: isViewingLiveWeek ? appState.picksViewModel.livePickCards : [:],
                teamRanks: appState.picksViewModel.teamRanks,
                currentUserId: currentUserId,
                allowsExpand: false,
                hiddenGameIds: hiddenGameIds(for: week),
                fillsAvailableWidth: true
            )
            .padding(.horizontal)
        }
    }

    private var yourStanding: StandingEntry? {
        appState.rankedStandings(weekly: true).first { $0.id == currentUserId }
    }

    private var theirStanding: StandingEntry {
        appState.rankedStandings(weekly: true).first { $0.id == opponent.id } ?? opponent
    }

    private var yourSeasonRecord: (wins: Int, losses: Int) {
        if let you = yourStanding {
            return (you.seasonWins, you.seasonLosses)
        }
        if let member = youMember {
            return (member.seasonWins, member.seasonLosses)
        }
        return (0, 0)
    }

    private var theirSeasonRecord: (wins: Int, losses: Int) {
        let them = theirStanding
        return (them.seasonWins, them.seasonLosses)
    }

    private var weeklyGapTitle: String {
        guard let week = selectedWeek, !isViewingLiveWeek else { return "This week" }
        return "Week \(week.weekNumber)"
    }

    private func weeklyRecord(for userId: String?) -> (wins: Int, losses: Int) {
        guard let userId else { return (0, 0) }
        let pick = picksByUserId[userId]
        return LeaguePickemsComparisonStats.weeklyRecord(
            picks: pick?.picks,
            games: displayGames,
            hiddenGameIds: selectedWeek.map { hiddenGameIds(for: $0) } ?? [],
            confidenceGameId: pick?.confidenceGameId
        )
    }

    private func recordText(wins: Int, losses: Int) -> String {
        "\(wins)-\(losses)"
    }

    private func pendingComparisonMessage(title: String, message: String) -> some View {
        PickemsCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.open")
                    .font(.title2)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(message)")
        }
    }

    private var comparisonHeader: some View {
        let youWeek = weeklyRecord(for: currentUserId)
        let themWeek = weeklyRecord(for: opponent.id)
        let youSeason = yourSeasonRecord
        let themSeason = theirSeasonRecord
        let youWeekText = recordText(wins: youWeek.wins, losses: youWeek.losses)
        let youSeasonText = recordText(wins: youSeason.wins, losses: youSeason.losses)
        let themWeekText = recordText(wins: themWeek.wins, losses: themWeek.losses)
        let themSeasonText = recordText(wins: themSeason.wins, losses: themSeason.losses)
        let weekGap = LeaguePickemsComparisonStats.gamesAhead(
            youWins: youWeek.wins,
            themWins: themWeek.wins
        )
        let seasonGap = LeaguePickemsComparisonStats.gamesAhead(
            youWins: youSeason.wins,
            themWins: themSeason.wins
        )
        let weekPhrase = LeaguePickemsComparisonStats.gapPhrase(gamesAhead: weekGap)
        let seasonPhrase = LeaguePickemsComparisonStats.gapPhrase(gamesAhead: seasonGap)
        return PickemsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    playerBlock(title: "You", weekly: youWeekText, season: youSeasonText)
                    playerBlock(title: opponentShortName, weekly: themWeekText, season: themSeasonText)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                HStack(alignment: .top, spacing: 12) {
                    gapBlock(title: weeklyGapTitle, phrase: weekPhrase, gamesAhead: weekGap)
                    gapBlock(title: "Season", phrase: seasonPhrase, gamesAhead: seasonGap)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "You \(youWeekText) \(weeklyGapTitle.lowercased()), \(youSeasonText) this season. \(opponent.displayName) \(themWeekText) \(weeklyGapTitle.lowercased()), \(themSeasonText) this season. \(weeklyGapTitle) \(weekPhrase). Season \(seasonPhrase)."
            )
        }
    }

    private func playerBlock(title: String, weekly: String, season: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
            Text(weekly)
                .font(.headline.monospacedDigit())
                .foregroundStyle(PickemsColors.textPrimary)
            Text("\(season) season")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gapBlock(title: String, phrase: String, gamesAhead: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
            Text(phrase)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(gapColor(gamesAhead))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gapColor(_ gamesAhead: Int) -> Color {
        if gamesAhead == 0 { return PickemsColors.textPrimary }
        return gamesAhead > 0 ? PickemsColors.success : PickemsColors.lost
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

    private static func member(from standing: StandingEntry) -> GroupMember {
        GroupMember(
            id: standing.id,
            displayName: standing.displayName,
            avatarColorHex: standing.avatarColorHex,
            role: .member,
            joinedAt: standing.joinedAt ?? Date(timeIntervalSince1970: 0),
            seasonWins: standing.seasonWins,
            seasonLosses: standing.seasonLosses,
            avatarImageURL: standing.avatarImageURL
        )
    }
}

nonisolated enum LeaguePickemsComparisonCopy {
    static func orderedWeeks(_ weeks: [WeekSummary]) -> [WeekSummary] {
        weeks.sorted {
            if $0.seasonYear != $1.seasonYear { return $0.seasonYear < $1.seasonYear }
            return $0.weekNumber < $1.weekNumber
        }
    }

    static func pendingBoard(isRolling: Bool, isSelection: Bool) -> (title: String, message: String) {
        let title = "This week's Pickems aren't public yet"
        if isSelection {
            if isRolling {
                return (
                    title,
                    "This comparison is empty until Selections close and Pickems start locking at each kickoff. Browse a previous week above."
                )
            }
            return (
                title,
                "This comparison is empty until Selections close and Pickems lock. Browse a previous week above."
            )
        }
        if isRolling {
            return (
                title,
                "Pickems appear here as each game kicks off. Until then, browse a previous week above."
            )
        }
        return (
            title,
            "This comparison opens after Pickems lock. Browse a previous week above."
        )
    }
}

nonisolated enum LeaguePickemsComparisonStats {
    static func samePickCount(
        games: [SlateGame],
        youPicks: [String: String]?,
        themPicks: [String: String]?,
        hiddenGameIds: Set<String>
    ) -> (same: Int, visible: Int) {
        let visible = games.filter { !hiddenGameIds.contains($0.id) }
        let you = youPicks ?? [:]
        let them = themPicks ?? [:]
        let same = visible.filter { game in
            guard let yours = you[game.id], !yours.isEmpty,
                  let theirs = them[game.id], !theirs.isEmpty else {
                return false
            }
            return yours == theirs
        }.count
        return (same, visible.count)
    }

    /// Win difference vs `them`. Positive means you are ahead. Losses do not create half-games:
    /// everyone is ranked by wins first, and a missed pick is skipped rather than a game in hand.
    static func gamesAhead(youWins: Int, themWins: Int) -> Int {
        StandingsGap.gamesAhead(youWins: youWins, themWins: themWins)
    }

    static func gapPhrase(gamesAhead: Int) -> String {
        StandingsGap.gapPhrase(gamesAhead: gamesAhead)
    }

    static func weeklyRecord(
        picks: [String: String]?,
        games: [SlateGame],
        hiddenGameIds: Set<String>,
        confidenceGameId: String? = nil
    ) -> (wins: Int, losses: Int) {
        let visible = games.filter { !hiddenGameIds.contains($0.id) }
        let scored = ScoringEngine.scorePicks(
            picks: picks ?? [:],
            games: visible,
            confidenceGameId: confidenceGameId
        )
        return (scored.wins, scored.losses)
    }
}
