import SwiftUI

struct GroupsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var showCommissionerSettings = false
    @State private var showCreateLeague = false
    @State private var manageExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if appState.groupService.groups.isEmpty {
                        EmptyStateView(
                            icon: "person.3.fill",
                            title: "No Groups Yet",
                            message: "Join or create a group to start competing.",
                            help: PickemsHelp.groupsOverview
                        )
                    } else {
                        groupPicker

                        if let group = appState.groupService.selectedGroup {
                            totalsHero(group)

                            LeaderboardView()

                            primaryActions(group)

                            manageSection(group)

                            DynastySectionView()
                                .padding(.horizontal)

                            SocialShareCard(
                                group: group,
                                standings: appState.groupService.standings
                            )
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .pickemsScreenBackground()
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HelpToolbarButton(topic: PickemsHelp.groupsOverview)
                }
            }
            .sheet(isPresented: $showCommissionerSettings) {
                // Always emit a concrete root view + explicit environment.
                // Empty `if let` sheet content crashed App Review 1.0 (EXC_BREAKPOINT in SheetBridge).
                Group {
                    if let group = appState.groupService.selectedGroup {
                        CommissionerSettingsView(group: group)
                    } else {
                        NavigationStack {
                            ContentUnavailableView(
                                "No League Selected",
                                systemImage: "person.3",
                                description: Text("Select a league, then open Commissioner Settings again.")
                            )
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { showCommissionerSettings = false }
                                }
                            }
                        }
                    }
                }
                .pickemsEnvironment(appState)
            }
            .sheet(isPresented: $showCreateLeague) {
                CreateGroupWizardView()
                    .pickemsEnvironment(appState)
            }
        }
    }

    // MARK: - Context bar

    private var groupPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Leagues")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(appState.groupService.groups) { group in
                        GroupChip(
                            name: group.name,
                            isSelected: appState.groupService.selectedGroup?.id == group.id
                        ) {
                            PickemsHaptics.selection()
                            appState.groupService.selectGroup(group)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Totals hero

    private var myStanding: StandingEntry? {
        guard let userId = appState.authService.currentUser?.id else { return nil }
        return appState.rankedStandings(weekly: true).first { $0.id == userId }
    }

    private func totalsHero(_ group: PickemGroup) -> some View {
        PickemsCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.title2.bold())
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text("\(group.memberCount) members · Code: \(group.inviteCode)")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)
                }

                if let entry = myStanding {
                    HStack(spacing: 0) {
                        totalsStat(
                            value: "\(entry.weeklyWins)–\(entry.weeklyLosses)",
                            label: "This Week"
                        )
                        totalsDivider
                        totalsStat(
                            value: "\(entry.seasonWins)–\(entry.seasonLosses)",
                            label: "Season"
                        )
                        totalsDivider
                        totalsStat(
                            value: "#\(entry.rank)",
                            label: entry.isTied ? "Rank (T)" : "Rank",
                            emphasize: true
                        )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Week \(entry.weeklyWins) to \(entry.weeklyLosses), season \(entry.seasonWins) to \(entry.seasonLosses), rank \(entry.rank)\(entry.isTied ? ", tied" : "")"
                    )
                } else {
                    Text("Standings appear after games are scored.")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
    }

    private func totalsStat(value: String, label: String, emphasize: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(emphasize ? PickemsTypography.rank : .title3.bold())
                .foregroundStyle(emphasize ? theme.accent : PickemsColors.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var totalsDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 36)
    }

    // MARK: - Primary actions

    private func primaryActions(_ group: PickemGroup) -> some View {
        HStack(spacing: 12) {
            InviteShareButton(group: group)
                .accessibilityHint("Share your invite code with friends")

            NavigationLink {
                MemberListView()
            } label: {
                Label("Members", systemImage: "person.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(PickemsColors.cardBackground)
                    .foregroundStyle(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("View league members and season records")
        }
        .padding(.horizontal)
    }

    // MARK: - Manage / secondary

    private func manageSection(_ group: PickemGroup) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    manageExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("Manage", systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PickemsColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .rotationEffect(.degrees(manageExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(PickemsColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(manageExpanded ? "Hide league tools" : "Show league tools and settings")
            .accessibilityAddTraits(.isButton)

            if manageExpanded {
                VStack(spacing: 8) {
                    if appState.isCommissioner {
                        manageRow(
                            title: "Commissioner Settings",
                            systemImage: "gearshape.fill",
                            hint: "Configure slate rules, deadlines, and tie-breakers"
                        ) {
                            showCommissionerSettings = true
                        }
                    }

                    manageNavRow(
                        title: "Stats",
                        systemImage: "chart.line.uptrend.xyaxis",
                        hint: "View your pick performance stats"
                    ) {
                        StatsView()
                    }

                    manageNavRow(
                        title: "Rivalry",
                        systemImage: "person.line.dotted.person.fill",
                        hint: "Compare records against another member"
                    ) {
                        RivalryView()
                    }

                    manageNavRow(
                        title: "Discover Public Leagues",
                        systemImage: "globe",
                        hint: "Browse public leagues you can join"
                    ) {
                        DiscoverLeaguesView()
                    }

                    manageRow(
                        title: "Join League",
                        systemImage: "person.badge.plus",
                        hint: "Enter an invite code for a different league"
                    ) {
                        appState.showJoinGroupSheet = true
                    }

                    manageRow(
                        title: "Create League",
                        systemImage: "plus.circle",
                        hint: "Start a brand new league you commission"
                    ) {
                        showCreateLeague = true
                    }

                    ShareAppButton(leagueName: group.name, label: "Invite via X")
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
    }

    private func manageRow(
        title: String,
        systemImage: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(PickemsColors.cardBackground)
                .foregroundStyle(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private func manageNavRow<Destination: View>(
        title: String,
        systemImage: String,
        hint: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(PickemsColors.cardBackground)
                .foregroundStyle(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }
}

struct GroupChip: View {
    @Environment(\.themePalette) private var theme
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? theme.accent : PickemsColors.cardBackground)
                .foregroundStyle(isSelected ? theme.onAccent : PickemsColors.textPrimary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Switch to this league")
    }
}

struct LeaderboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var showWeekly = true

    private var displayEntries: [StandingEntry] {
        appState.rankedStandings(weekly: showWeekly)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Leaderboard",
                subtitle: showWeekly ? "This week's spread record" : "Season standings",
                help: PickemsHelp.leaderboard
            )

            Picker("Standings", selection: $showWeekly) {
                Text("This Week").tag(true)
                Text("Season").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityLabel("Standings period")

            if !displayEntries.isEmpty {
                ForEach(displayEntries) { entry in
                    VStack(spacing: 4) {
                        LeaderboardRow(entry: entry, showWeekly: showWeekly)
                        if entry.isTied && appState.isCommissioner
                            && appState.groupService.selectedGroup?.rules.tieBreaker == .commissionerOverride {
                            Button("Resolve Tie (Commissioner)") {
                                PickemsHaptics.lightImpact()
                                Task {
                                    guard let groupId = appState.groupService.selectedGroup?.id else { return }
                                    do {
                                        try await appState.groupService.resolveTie(
                                            groupId: groupId,
                                            standingUserId: entry.id
                                        )
                                    } catch {
                                        // Leaderboard refreshes from Firestore listener
                                    }
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                            .accessibilityHint("Manually break a tie between players with the same record")
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                EmptyStateView(
                    icon: "chart.bar.fill",
                    title: "No Standings Yet",
                    message: "Standings appear after games are scored.",
                    help: PickemsHelp.leaderboard
                )
            }
        }
        .task(id: appState.groupService.currentWeek?.id) {
            guard let group = appState.groupService.selectedGroup,
                  let week = appState.groupService.currentWeek else { return }
            await appState.pickService.loadAllPicks(groupId: group.id, weekId: week.id)
        }
    }
}
