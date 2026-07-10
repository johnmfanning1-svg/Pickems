import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    weekHeader

                    greetingHeader

                    quickActionsSection

                    if let week = appState.groupService.currentWeek,
                       week.status == .scored,
                       let group = appState.groupService.selectedGroup {
                        WeekRecapCard(recapText: WeekRecapGenerator.recap(
                            groupName: group.name,
                            week: week,
                            standings: appState.groupService.standings,
                            userId: appState.authService.currentUser?.id
                        ))

                        if let shareSource = appState.weeklyShareSource() {
                            ShareResultsButton(source: shareSource)
                                .padding(.horizontal)
                        }
                    }

                    groupCard

                    if viewModel.isLoading && viewModel.liveGames.isEmpty {
                        ProgressView("Loading CFB scores…")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .accessibilityLabel("Loading college football scores")
                    } else if let error = viewModel.errorMessage, viewModel.liveGames.isEmpty {
                        ContextualTipBanner(
                            icon: "exclamationmark.triangle.fill",
                            message: error
                        )
                    }

                    if !viewModel.newsItems.isEmpty {
                        NewsFeedSection(items: viewModel.newsItems)
                    }

                    if !viewModel.slateGames.isEmpty {
                        LiveScoreboardSection(
                            games: viewModel.slateGames,
                            title: "Your Slate",
                            subtitle: "Games you picked this week",
                            help: PickemsHelp.liveScores
                        )
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
                .padding(.vertical)
            }
            .pickemsScreenBackground()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
            }
            .onDisappear {
                viewModel.stopLiveUpdates()
            }
        }
    }

    private var refreshKey: String {
        let groupId = appState.groupService.selectedGroup?.id ?? ""
        let weekId = appState.groupService.currentWeek?.id ?? ""
        return "\(groupId)-\(weekId)"
    }

    private var greetingHeader: some View {
        Text("Hi, \(appState.authService.currentUser?.displayName ?? "Player")")
            .font(.title2.bold())
            .foregroundStyle(PickemsColors.textPrimary)
            .padding(.horizontal)
            .accessibilityAddTraits(.isHeader)
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Quick Actions",
                subtitle: "Jump to picks or standings"
            )

            HStack(spacing: 12) {
                QuickActionCard(
                    title: "Submit Picks",
                    icon: "checkmark.circle.fill",
                    color: theme.accent,
                    accessibilityHint: "Opens the Picks tab to submit your spread picks"
                ) {
                    PickemsHaptics.selection()
                    appState.selectedTab = .picks
                }
                QuickActionCard(
                    title: "Leaderboard",
                    icon: "trophy.fill",
                    color: PickemsColors.warning,
                    accessibilityHint: "Opens the Groups tab to view standings"
                ) {
                    PickemsHaptics.selection()
                    appState.selectedTab = .groups
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var weekHeader: some View {
        if let cfbWeek = viewModel.cfbWeek ?? appState.groupService.cfbWeek {
            SeasonWeekHeader(label: cfbWeek.label)
        } else if let week = appState.groupService.currentWeek {
            SeasonWeekHeader(label: week.displayLabel)
        }
    }

    @ViewBuilder
    private var groupCard: some View {
        if let group = appState.groupService.selectedGroup {
            VStack(alignment: .leading, spacing: 8) {
                PickemsSectionHeader(
                    title: group.name,
                    subtitle: "\(group.memberCount) members",
                    help: PickemsHelp.weekStatus
                )

                PickemsCard {
                    HStack {
                        if let week = appState.groupService.currentWeek {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(weekStatusLabel(week.status))
                                    .font(.subheadline)
                                    .foregroundStyle(PickemsColors.textPrimary)
                                StatusBadge(
                                    text: week.status.rawValue.capitalized,
                                    color: statusColor(week.status)
                                )
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal)
            }
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

struct QuickActionCard: View {
    let title: String
    let icon: String
    let color: Color
    var accessibilityHint: String = ""
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(PickemsColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}
