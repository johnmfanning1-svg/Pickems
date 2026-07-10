import SwiftUI

/// Redesigned Home: first viewport = brand pulse for this week only.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var viewModel = HomeViewModel()
    @State private var coverMoment = CoverMomentPresenter()
    @State private var showMore = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroPulse
                        .pickemsAppear()

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

                    if showMore {
                        moreSections
                    } else {
                        Button {
                            withAnimation(.easeInOut) { showMore = true }
                        } label: {
                            Label("Scores, news & standings", systemImage: "chevron.down.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.accent)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical)
            }
            .pickemsScreenBackground()
            .navigationTitle("Pickems")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    groupSwitcher
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HelpToolbarButton(topic: PickemsHelp.homeOverview)
                }
            }
            .refreshable {
                await viewModel.refresh(appState: appState)
            }
            .task(id: refreshKey) {
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
            }
        }
    }

    private var refreshKey: String {
        let groupId = appState.groupService.selectedGroup?.id ?? ""
        let weekId = appState.groupService.currentWeek?.id ?? ""
        return "\(groupId)-\(weekId)"
    }

    private var heroPulse: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let team = appState.authService.currentUser?.favoriteTeam {
                HStack(spacing: 8) {
                    if let url = URL(string: team.resolvedLogoURL) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit()
                            }
                        }
                        .frame(width: 28, height: 28)
                    }
                    Text("Pickems")
                        .font(PickemsTypography.display(34))
                        .foregroundStyle(PickemsColors.textPrimary)
                }
                .padding(.horizontal)
            } else {
                Text("Pickems")
                    .font(PickemsTypography.display(34))
                    .foregroundStyle(PickemsColors.textPrimary)
                    .padding(.horizontal)
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
                                    Text(weekStatusLabel(week.status))
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
                EmptyStateView(
                    icon: "person.3.fill",
                    title: "Join a league",
                    message: "Create or join a group to start this week's pulse."
                )
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
                        LeaderboardRow(entry: entry, showWeekly: true)
                            .padding(.horizontal)
                    }
                }
            }
        }
        .pickemsAppear()
    }

    private var groupSwitcher: some View {
        Menu {
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
        } label: {
            Image(systemName: "arrow.left.arrow.right.circle")
                .foregroundStyle(theme.accent)
        }
        .accessibilityLabel("Switch league")
    }

    private var myStanding: StandingEntry? {
        guard let userId = appState.authService.currentUser?.id else { return nil }
        return appState.rankedStandings(weekly: true).first { $0.id == userId }
    }

    private var ctaTitle: String {
        switch appState.groupService.currentWeek?.status {
        case .selection: return "Build Slate"
        case .picking: return "Submit Picks"
        case .locked: return "Watch Live"
        case .scored: return "See Results"
        case .none: return "Open Picks"
        }
    }

    private func weekStatusLabel(_ status: WeekStatus) -> String {
        switch status {
        case .selection: return "Building this week's slate"
        case .picking: return "Submit your spread picks"
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
