import SwiftUI

/// Redesigned Home: first viewport = brand pulse for this week only.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var viewModel = HomeViewModel()
    @State private var coverMoment = CoverMomentPresenter()
    @State private var scoreboardFilter: HomeScoreboardFilter = .default
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                        WeekRecapCard(recapText: WeekRecapGenerator.recap(
                            groupName: group.name,
                            week: week,
                            standings: appState.groupService.standings,
                            userId: appState.authService.currentUser?.id
                        ))
                        .pickemsAppear()

                        if let awards = week.awards {
                            WeekAwardsBanner(awards: awards)
                                .padding(.horizontal)
                        } else if week.status == .scored {
                            let computed = WeekAwardsEngine.compute(
                                picks: appState.pickService.allPicks,
                                games: appState.pickService.slateGames,
                                members: appState.groupService.members
                            )
                            WeekAwardsBanner(awards: WeekAwards(
                                sharpshooterUserId: computed.sharpshooterUserId,
                                heartbreakerUserId: computed.heartbreakerUserId,
                                contrarianUserId: computed.contrarianUserId
                            ))
                            .padding(.horizontal)
                        }

                        if let shareSource = appState.weeklyShareSource() {
                            ShareResultsButton(source: shareSource)
                                .padding(.horizontal)
                        }
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
                viewModel.startLiveUpdates(appState: appState)
                appState.publishSurfaces()
            }
            .onAppear {
                viewModel.startLiveUpdates(appState: appState)
            }
            .onChange(of: appState.selectedTab) { _, tab in
                if tab == .home {
                    viewModel.startLiveUpdates(appState: appState)
                }
            }
            .onChange(of: appState.pickService.userPick) { _, _ in
                Task { await viewModel.refresh(appState: appState) }
            }
            .onChange(of: appState.pickService.slateGames) { _, _ in
                coverMoment.observe(appState: appState)
                appState.publishSurfaces()
                Task { await viewModel.refresh(appState: appState) }
            }
            .onChange(of: appState.groupService.standings) { _, _ in
                appState.publishSurfaces()
            }
        }
    }

    private var heroPulse: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                brandMark
                Text("Pickems")
                    .font(PickemsTypography.display(34))
                    .foregroundStyle(PickemsColors.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pickems")

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
                    VStack(alignment: .leading, spacing: 12) {
                        if let week = appState.groupService.currentWeek {
                            Text(week.displayLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PickemsColors.textSecondary)
                        }

                        if let entry = myStanding {
                            HStack(alignment: .firstTextBaseline) {
                                Text("#\(entry.rank)")
                                    .font(PickemsTypography.rank)
                                    .foregroundStyle(theme.accent)
                                    .pickemsRankMotion(trigger: entry.rank)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(entry.weeklyWins)–\(entry.weeklyLosses) this week")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Season \(entry.seasonWins)–\(entry.seasonLosses)")
                                        .font(.caption)
                                        .foregroundStyle(PickemsColors.textSecondary)
                                }
                                Spacer()
                            }
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
                VStack(spacing: 16) {
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
        VStack(alignment: .leading, spacing: 24) {
            if !viewModel.newsItems.isEmpty {
                NewsFeedSection(items: viewModel.newsItems)
            }

            if viewModel.isLoading && viewModel.liveGames.isEmpty {
                ProgressView("Loading scores…")
                    .tint(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .accessibilityLabel("Loading scores")
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
                VStack(alignment: .leading, spacing: 12) {
                    PickemsSectionHeader(
                        title: "Top Standings",
                        subtitle: "This week's leaders",
                        help: PickemsHelp.standingsPreview
                    )
                    ForEach(Array(topEntries)) { entry in
                        LeaderboardRow(
                            entry: entry,
                            showWeekly: true,
                            isCommissioner: entry.id == appState.groupService.selectedGroup?.commissionerId
                        )
                            .padding(.horizontal)
                    }
                }
            }
        }
        .pickemsAppear()
    }

    @ViewBuilder
    private var brandMark: some View {
        if let team = appState.authService.currentUser?.favoriteTeam,
           let url = URL(string: team.resolvedLogoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
        } else {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
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
        return HomeCTAResolver.resolve(
            week: week,
            isCommissioner: appState.isCommissioner,
            didSubmitNominations: appState.pickService.didSubmitNominations,
            userNominationCount: userNoms,
            pickCount: appState.pickService.userPick?.picks.count ?? 0,
            slateCount: appState.pickService.slateGames.count,
            pickemsLocked: PickDeadlineCalculator.isPast(week?.pickDeadline),
            picksSubmitted: appState.pickService.userPick?.isLocked == true
        )
    }
}
