import SwiftUI

/// Redesigned Home: first viewport = brand pulse for this week only.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var viewModel = HomeViewModel()
    @State private var coverMoment = CoverMomentPresenter()
    @State private var showFavoriteTeamPicker = false
    @State private var showJoinSheet = false
    @State private var showCreateWizard = false

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
                ToolbarItem(placement: .topBarTrailing) {
                    HelpToolbarButton(topic: PickemsHelp.homeOverview)
                }
            }
            .refreshable {
                await viewModel.refresh(appState: appState)
            }
            .task(id: appState.groupService.selectedGroup?.id) {
                await appState.syncSelectedWeek()
                viewModel.startLiveUpdates(appState: appState)
                WidgetSnapshotService.publish(from: appState)
                LiveActivityController.sync(from: appState)
            }
            .onChange(of: appState.pickService.slateGames) { _, _ in
                coverMoment.observe(appState: appState)
                WidgetSnapshotService.publish(from: appState)
                LiveActivityController.sync(from: appState)
            }
            .onChange(of: appState.groupService.standings) { _, _ in
                WidgetSnapshotService.publish(from: appState)
                LiveActivityController.sync(from: appState)
            }
            .onDisappear {
                viewModel.stopLiveUpdates()
            }
            .sheet(isPresented: $coverMoment.isPresented) {
                CoverMomentView(
                    gameLabel: coverMoment.gameLabel,
                    resultTitle: coverMoment.resultTitle,
                    recordText: coverMoment.recordText,
                    rankText: coverMoment.rankText,
                    shareSource: coverMoment.shareSource
                )
                .pickemsEnvironment(appState)
            }
            .sheet(isPresented: $showFavoriteTeamPicker) {
                FavoriteTeamPickerView()
                    .pickemsEnvironment(appState)
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinGroupSheet(initialCode: "")
                    .pickemsEnvironment(appState)
            }
            .sheet(isPresented: $showCreateWizard) {
                CreateGroupWizardView()
                    .pickemsEnvironment(appState)
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
                    showFavoriteTeamPicker = true
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

            if let group = appState.groupService.selectedGroup {
                PickemsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name)
                                    .font(.headline)
                                if let week = appState.groupService.currentWeek {
                                    Text(weekStatusLabel(week))
                                        .font(.subheadline)
                                        .foregroundStyle(PickemsColors.textSecondary)
                                }
                            }
                            Spacer()
                            if let week = appState.groupService.currentWeek {
                                StatusBadge(text: week.status.rawValue.capitalized, color: statusColor(week.status))
                                    .pickemsPulse(enabled: week.status == .locked)
                            }
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

                        HStack(spacing: 10) {
                            PrimaryButton(title: ctaTitle) {
                                appState.selectedTab = .picks
                            }
                        }
                    }
                }
                .padding(.horizontal)
            } else {
                VStack(spacing: 16) {
                    EmptyStateView(
                        icon: "person.3.fill",
                        title: "Join a league",
                        message: "Create or join a group to start this week's pulse."
                    )
                    HStack(spacing: 12) {
                        Button {
                            showJoinSheet = true
                        } label: {
                            Label("Join / Search", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            showCreateWizard = true
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
            if !viewModel.slateGames.isEmpty {
                LiveScoreboardSection(
                    games: viewModel.slateGames,
                    title: "Your Slate",
                    subtitle: "Games you picked this week",
                    help: PickemsHelp.liveScores
                )
            }

            if !viewModel.newsItems.isEmpty {
                NewsFeedSection(items: viewModel.newsItems)
            }

            LiveScoreboardSection(
                games: viewModel.slateGames.isEmpty
                    ? viewModel.liveGames
                    : Array(viewModel.liveGames.filter { !$0.isSlateGame }.prefix(6)),
                title: viewModel.slateGames.isEmpty ? "CFB This Week" : "Other Games",
                subtitle: viewModel.slateGames.isEmpty
                    ? "Live scores from ESPN"
                    : "More games on the board",
                help: PickemsHelp.liveScores
            )

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
                    showJoinSheet = true
                } label: {
                    Label("Join / Search", systemImage: "magnifyingglass")
                }
                Button {
                    showCreateWizard = true
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

    private var ctaTitle: String {
        guard let week = appState.groupService.currentWeek else { return "Open Picks" }
        switch week.status {
        case .selection: return "Build Slate"
        case .picking:
            if PickDeadlineCalculator.isPast(week.pickDeadline) {
                return "View Picks"
            }
            if appState.pickService.userPick?.isLocked == true {
                return "Edit Picks"
            }
            return "Submit Picks"
        case .locked: return "Watch Live"
        case .scored: return "See Results"
        }
    }

    private func weekStatusLabel(_ week: WeekSummary) -> String {
        switch week.status {
        case .selection: return "Building this week's slate"
        case .picking:
            if PickDeadlineCalculator.isPast(week.pickDeadline) {
                return "Pick deadline has passed"
            }
            if appState.pickService.userPick?.isLocked == true {
                return "Picks submitted — edit until lock"
            }
            return "Submit your spread picks"
        case .locked: return "Games in progress"
        case .scored: return "Week complete"
        }
    }

    private func statusColor(_ status: WeekStatus) -> Color {
        switch status {
        case .selection: return PickemsColors.warning
        case .picking: return theme.accent
        case .locked: return PickemsColors.textSecondary
        case .scored: return PickemsColors.success
        }
    }
}
