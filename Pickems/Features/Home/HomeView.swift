import SwiftUI

/// Redesigned Home: first viewport = brand pulse for this week only.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = HomeViewModel()
    @State private var coverMoment = CoverMomentPresenter()
    @State private var scoreboardFilter: HomeScoreboardFilter = .default
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PickemsSpacing.lg) {
                    heroPulse
                        .pickemsAppear()

                    if let error = viewModel.errorMessage {
                        ContextualTipBanner(
                            icon: "exclamationmark.triangle.fill",
                            message: error
                        )
                        .padding(.horizontal)
                    }

                    if let week = appState.groupService.currentWeek,
                       week.status == .scored,
                       let group = appState.groupService.selectedGroup {
                        HomeScoredWeekSection(week: week, group: group)
                            .pickemsAppear()
                    }

                    // Scores, CFB This Week, and news stay expanded by default.
                    moreSections
                }
                .padding(.top, 8)
                .padding(.bottom)
            }
            .pickemsScreenBackground()
            // Title is the league switcher when the user has leagues; brand stays in `heroPulse`.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    groupTitleMenu
                }
                HelpToolbarItem(topic: PickemsHelp.homeOverview)
            }
            .pickemsRefreshable(isRefreshing: $isRefreshing) {
                await viewModel.refresh(appState: appState, showLoading: viewModel.liveGames.isEmpty, forceRefresh: true)
                appState.publishSurfaces()
            }
            .task(id: appState.groupService.selectedGroup?.id) {
                await appState.syncSelectedWeek()
                updateLivePolling()
                appState.publishSurfaces()
            }
            .onAppear {
                updateLivePolling()
                coverMoment.observe(
                    appState: appState,
                    isForeground: scenePhase == .active,
                    absorbCurrentlyFinal: true
                )
            }
            .onDisappear {
                viewModel.stopLiveUpdates()
            }
            .onChange(of: appState.selectedTab) { _, _ in
                updateLivePolling()
            }
            .onChange(of: scenePhase) { old, new in
                updateLivePolling()
                coverMoment.observe(
                    appState: appState,
                    isForeground: new == .active,
                    absorbCurrentlyFinal: new == .active && old != .active
                )
            }
            .onChange(of: appState.pickService.userPick) { _, _ in
                Task { await viewModel.refresh(appState: appState) }
            }
            .onChange(of: appState.pickService.slateGames) { _, _ in
                coverMoment.observe(
                    appState: appState,
                    isForeground: scenePhase == .active,
                    absorbCurrentlyFinal: false
                )
                appState.publishSurfaces()
                Task { await viewModel.refresh(appState: appState) }
            }
            .onChange(of: appState.groupService.standings) { _, _ in
                appState.publishSurfaces()
            }
        }
    }

    private func updateLivePolling() {
        if LiveRefreshPolicy.shouldPollLiveScores(
            isHomeTab: appState.selectedTab == .home,
            isActive: scenePhase == .active
        ) {
            viewModel.startLiveUpdates(appState: appState)
        } else {
            viewModel.stopLiveUpdates()
        }
    }

    private var heroPulse: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            if appState.groupService.selectedGroup == nil {
                HStack(spacing: 10) {
                    brandMark(size: 24)
                    Text("Pickems")
                        .font(PickemsTypography.display(22))
                        .foregroundStyle(PickemsColors.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PickemsSpacing.md)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pickems")
            }

            if appState.authService.currentUser?.favoriteTeam == nil {
                Button {
                    appState.present(.favoriteTeam(isOnboardingPrompt: false))
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose your favorite team")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PickemsColors.textPrimary)
                            Text("Theme Pickems around your colors")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                    .padding(14)
                    .background(PickemsColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .accessibilityHint("Opens the favorite team picker")
            }

            if let cfbWeek = viewModel.cfbWeek ?? appState.groupService.cfbWeek {
                Text(cfbWeek.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .padding(.horizontal)
            }

            if appState.groupService.selectedGroup != nil {
                PickemsCard {
                    VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
                        if let week = appState.groupService.currentWeek {
                            Text(week.displayLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PickemsColors.textSecondary)
                        }

                        if let entry = myStanding {
                            pulseRank(entry)
                        }

                        let cta = homeCTA
                        if let tab = cta.destinationTab {
                            PrimaryButton(title: cta.title) {
                                appState.selectedTab = tab
                            }
                        } else {
                            Text(cta.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PickemsColors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal)
            } else {
                VStack(spacing: PickemsSpacing.sm) {
                    EmptyStateView(
                        icon: "person.3.fill",
                        title: "Join a league",
                        message: "Create or join a league to start this week's pulse."
                    )
                    HStack(spacing: 12) {
                        Button {
                            appState.present(.joinGroup)
                        } label: {
                            Label("Join / Search", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            appState.present(.createLeague)
                        } label: {
                            Label("Create", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var moreSections: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.lg) {
            if !viewModel.newsItems.isEmpty {
                NewsFeedSection(items: viewModel.newsItems)
            }

            if viewModel.isLoading && viewModel.liveGames.isEmpty {
                HomeScoreboardPlaceholder()
            } else if !viewModel.liveGames.isEmpty || viewModel.isRefreshingContent {
                LiveScoreboardSection(
                    games: viewModel.liveGames,
                    title: "CFB This Week",
                    subtitle: scoreboardSubtitle,
                    scoreboardFilter: $scoreboardFilter,
                    seasonWeeks: viewModel.seasonWeeks,
                    selectedWeek: viewModel.selectedBrowseWeek,
                    weekMenuTitle: viewModel.scoreboardWeekLabel,
                    onSelectWeek: { week in
                        viewModel.selectBrowseWeek(week, appState: appState)
                    },
                    showsRefreshSpinner: viewModel.isRefreshingContent
                )
            }

            if appState.groupService.standings != nil {
                let topEntries = appState.rankedStandings(weekly: true).prefix(3)
                VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
                    PickemsSectionHeader(
                        title: "Top Standings",
                        subtitle: "This week's leaders",
                        help: PickemsHelp.standingsPreview
                    )
                    ForEach(Array(topEntries)) { entry in
                        LeaderboardRow(
                            entry: entry,
                            showWeekly: true,
                            isCommissioner: entry.id == appState.groupService.selectedGroup?.commissionerId,
                            coordinatorRole: appState.groupService.selectedGroup?.coordinatorRole(for: entry.id)
                        )
                            .padding(.horizontal)
                    }
                }
            }
        }
        .pickemsAppear()
    }

    @ViewBuilder
    private func brandMark(size: CGFloat) -> some View {
        if let team = appState.authService.currentUser?.favoriteTeam,
           let url = URL(string: team.resolvedLogoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: size))
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
        }
    }

    private var navTitleText: String {
        appState.groupService.selectedGroup?.name ?? "Pickems"
    }

    private var groupTitleMenu: some View {
        Menu {
            if !appState.groupService.groups.isEmpty {
                Section("Your leagues") {
                    ForEach(appState.groupService.groups) { group in
                        Button {
                            appState.groupService.selectGroup(group)
                        } label: {
                            if appState.groupService.selectedGroup?.id == group.id {
                                Label(group.name, systemImage: "checkmark")
                            } else {
                                Text(group.name)
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    appState.present(.joinGroup)
                } label: {
                    Label("Join / Search", systemImage: "magnifyingglass")
                }
                Button {
                    appState.present(.createLeague)
                } label: {
                    Label("Create league", systemImage: "plus.circle")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(navTitleText)
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityLabel(navTitleText)
        .accessibilityHint("Switch, join, or create a league")
    }

    /// Streak stays off Home. `PlayerSeasonStats` is built by Stats and Rivalry into local
    /// state, and `GroupService` does not keep a copy. Loading it here would add a season of reads.
    private func pulseRank(_ entry: StandingEntry) -> some View {
        let pulse = PulseRankCopy.display(
            entry: entry,
            board: appState.rankedStandings(weekly: true)
        )
        return HStack(alignment: .firstTextBaseline) {
            Text(pulse.rankText)
                .font(PickemsTypography.rank)
                .foregroundStyle(theme.accent)
                .accessibilityLabel(pulse.accessibilityRank)
                .pulseRankMotion(pulse.animatableRank)
            VStack(alignment: .leading, spacing: 2) {
                Text(pulse.detailText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text("Season \(entry.seasonWins)–\(entry.seasonLosses)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PickemsColors.textSecondary)
            }
            Spacer()
        }
    }

    private var myStanding: StandingEntry? {
        guard let userId = appState.authService.currentUser?.id else { return nil }
        return appState.rankedStandings(weekly: true).first { $0.id == userId }
    }

    private var scoreboardSubtitle: String {
        switch scoreboardFilter {
        case .power4: return "Power 4 — live scores from ESPN"
        case .top25: return "Top 25 matchups"
        case .myPicks: return "Your Pickems this week"
        case .groupSlate: return "Your league's slate"
        case .all: return "All FBS games this week"
        case .conference(let id):
            let name = ESPNConferenceCatalog.conference(id: id)?.shortName ?? "Conference"
            return "\(name) games this week"
        }
    }

    private var homeCTA: HomeCTA {
        let week = appState.groupService.currentWeek
        let userId = appState.currentUserId
        let userNoms = appState.pickService.nominations.filter { $0.submittedBy == userId }.count
        let slate = appState.pickService.slateGames
        let ineligible = Set(slate.filter { !appState.picksViewModel.allowsPicks($0) }.map(\.id))
        let picks = appState.pickService.userPick?.picks ?? [:]
        let pickCount = ineligible.isEmpty
            ? picks.count
            : picks.keys.filter { !ineligible.contains($0) }.count
        return HomeCTAResolver.resolve(
            week: week,
            isCommissioner: appState.canOperateWeek,
            didSubmitNominations: appState.pickService.didSubmitNominations,
            userNominationCount: userNoms,
            pickCount: pickCount,
            slateCount: slate.count - ineligible.count,
            pickemsLocked: week.map { WeekTransition.arePicksFullyLocked($0) } ?? false,
            picksSubmitted: appState.pickService.userPick?.isLocked == true
        )
    }
}

private extension View {
    @ViewBuilder
    func pulseRankMotion(_ rank: Int?) -> some View {
        if let rank {
            self.pickemsRankMotion(trigger: rank)
        } else {
            self
        }
    }
}

private struct HomeScoredWeekSection: View {
    let week: WeekSummary
    let group: PickemGroup
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedWeekWin: PresentedWeekWin?

    private var awards: WeekAwards? {
        if let stored = week.awards,
           stored.sharpshooterUserId != nil
            || stored.heartbreakerUserId != nil
            || stored.contrarianUserId != nil {
            return stored
        }
        let computed = WeekAwardsEngine.compute(
            picks: appState.pickService.allPicks,
            games: appState.pickService.slateGames,
            members: appState.groupService.members,
            pickMode: appState.pickMode(for: week)
        )
        let awards = WeekAwards(
            sharpshooterUserId: computed.sharpshooterUserId,
            heartbreakerUserId: computed.heartbreakerUserId,
            contrarianUserId: computed.contrarianUserId
        )
        if awards.sharpshooterUserId != nil
            || awards.heartbreakerUserId != nil
            || awards.contrarianUserId != nil {
            return awards
        }
        return nil
    }

    private var rankedEntries: [StandingEntry] {
        appState.rankedStandings(weekly: true)
    }

    private var myEntry: StandingEntry? {
        guard let userId = appState.currentUserId else { return nil }
        return rankedEntries.first { $0.id == userId }
    }

    private var weekWinKind: CelebrationPolicy.WeekWinKind? {
        guard let userId = appState.currentUserId else { return nil }
        let entries = rankedEntries.map {
            CelebrationPolicy.WeekBoardEntry(
                id: $0.id,
                rank: $0.rank,
                isTied: $0.isTied,
                weeklyWins: $0.weeklyWins,
                weeklyLosses: $0.weeklyLosses
            )
        }
        return CelebrationPolicy.weekWinKind(
            entries: entries,
            userId: userId,
            weekStatus: week.status
        )
    }

    private var isPerfectSaturday: Bool {
        guard let entry = myEntry else { return false }
        return StreakEngine.isPerfectSaturday(
            wins: entry.weeklyWins,
            losses: entry.weeklyLosses,
            slateSize: appState.pickService.slateGames.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            if let presentedWeekWin {
                WeekWinCard(
                    title: presentedWeekWin.title,
                    wins: presentedWeekWin.wins,
                    losses: presentedWeekWin.losses,
                    isPerfect: presentedWeekWin.isPerfect,
                    shareSource: appState.weeklyShareSource(),
                    showsBurst: !reduceMotion
                )
                .padding(.horizontal, PickemsSpacing.md)
            }

            if appState.isCommissioner {
                if presentedWeekWin == nil, isPerfectSaturday {
                    StreakBadgeView(streak: 0, isPerfect: true)
                        .padding(.horizontal, PickemsSpacing.md)
                }
                CommissionerLeagueRecapPanel(
                    group: group,
                    week: week,
                    entries: rankedEntries,
                    picks: appState.pickService.allPicks,
                    games: appState.pickService.slateGames,
                    awards: awards
                )
            } else {
                WeekRecapCard(
                    recapText: WeekRecapGenerator.recap(
                        groupName: group.name,
                        week: week,
                        standings: appState.groupService.standings,
                        userId: appState.currentUserId,
                        pickMode: appState.pickMode(for: week)
                    ),
                    showsPerfectSaturday: presentedWeekWin == nil && isPerfectSaturday
                )
                if let awards {
                    WeekAwardsBanner(awards: awards)
                        .padding(.horizontal)
                }
                if presentedWeekWin == nil, let shareSource = appState.weeklyShareSource() {
                    ShareResultsButton(source: shareSource)
                        .padding(.horizontal)
                }
            }
        }
        .onAppear(perform: revealWeekWinIfNeeded)
    }

    private func revealWeekWinIfNeeded() {
        guard presentedWeekWin == nil, let kind = weekWinKind, let entry = myEntry else { return }
        let already = CelebrationStore.hasCelebratedWeekWin(groupId: group.id, weekId: week.id)
        guard CelebrationPolicy.shouldShowWeekWin(kind: kind, alreadyCelebrated: already) else { return }
        presentedWeekWin = PresentedWeekWin(
            title: kind.title(weekNumber: week.weekNumber),
            wins: entry.weeklyWins,
            losses: entry.weeklyLosses,
            isPerfect: isPerfectSaturday
        )
        CelebrationStore.markWeekWinCelebrated(groupId: group.id, weekId: week.id)
    }
}

private struct PresentedWeekWin: Equatable {
    var title: String
    var wins: Int
    var losses: Int
    var isPerfect: Bool
}

private struct WeekWinCard: View {
    let title: String
    let wins: Int
    let losses: Int
    let isPerfect: Bool
    let shareSource: ShareSource?
    let showsBurst: Bool
    @Environment(\.themePalette) private var theme

    var body: some View {
        PickemsCard {
            VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
                HStack(spacing: PickemsSpacing.xs) {
                    Image(systemName: "crown.fill")
                        .font(.title3)
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(PickemsTypography.display(28))
                        .foregroundStyle(PickemsColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(CelebrationPolicy.recordLine(wins: wins, losses: losses))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(PickemsColors.textPrimary)
                if isPerfect {
                    StreakBadgeView(streak: 0, isPerfect: true)
                }
                if let shareSource {
                    ShareResultsButton(source: shareSource)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .top) {
            if showsBurst {
                WeekWinBurst(accent: theme.accent)
                    .offset(y: -8)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Short accent-and-white burst. Overlaid so the card does not jump when it ends.
private struct WeekWinBurst: View {
    let accent: Color
    private let started = Date()
    private let count = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(started)
            let progress = min(1, max(0, elapsed / 0.9))
            Canvas { context, size in
                guard progress < 1 else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.72)
                for index in 0..<count {
                    let angle = (Double(index) / Double(count)) * Double.pi * 2
                    let reach = 26 + Double(index % 4) * 12
                    let x = origin.x + CGFloat(cos(angle) * reach * progress)
                    let y = origin.y + CGFloat(sin(angle) * reach * 0.45 * progress) - CGFloat(16 * progress)
                    let width: CGFloat = index.isMultiple(of: 3) ? 8 : 5
                    let rect = CGRect(x: x - width / 2, y: y - 1.5, width: width, height: 3)
                    var burst = context
                    burst.opacity = 1 - progress
                    let color = index.isMultiple(of: 2) ? accent : Color.white
                    burst.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                }
            }
        }
        .frame(height: 52)
        .accessibilityHidden(true)
    }
}

private struct HomeScoreboardPlaceholder: View {
    var body: some View {
        VStack(spacing: PickemsSpacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                PickemsCard {
                    HStack(spacing: PickemsSpacing.sm) {
                        teamColumn
                        VStack(spacing: PickemsSpacing.xxs) {
                            Text("Sat 12:00")
                            Text("ESPN")
                            Text("TEAM -1.5")
                        }
                        .frame(minWidth: 80)
                        teamColumn
                    }
                }
                .redacted(reason: .placeholder)
                .padding(.horizontal, PickemsSpacing.md)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading scores")
    }

    private var teamColumn: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 6)
                .frame(width: 32, height: 32)
            Text("Away")
            Text("00")
        }
        .frame(maxWidth: .infinity)
    }
}
