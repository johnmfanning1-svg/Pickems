import SwiftUI

struct GroupsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var showCommissionerSettings = false

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
                            groupHeader(group)

                            if appState.isCommissioner {
                                SecondaryButton("Commissioner Settings", icon: "gearshape.fill") {
                                    showCommissionerSettings = true
                                }
                                .padding(.horizontal)
                                .accessibilityHint("Configure slate rules, deadlines, and tie-breakers")
                            }

                            HStack(spacing: 12) {
                                NavigationLink {
                                    StatsView()
                                } label: {
                                    Label("Stats", systemImage: "chart.line.uptrend.xyaxis")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(PickemsColors.cardBackground)
                                        .foregroundStyle(theme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    RivalryView()
                                } label: {
                                    Label("Rivalry", systemImage: "person.line.dotted.person.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(PickemsColors.cardBackground)
                                        .foregroundStyle(theme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)

                            HStack(spacing: 12) {
                                NavigationLink {
                                    DiscoverLeaguesView()
                                } label: {
                                    Label("Discover", systemImage: "globe")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(PickemsColors.cardBackground)
                                        .foregroundStyle(theme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    appState.showJoinGroupSheet = true
                                } label: {
                                    Label("Join", systemImage: "person.badge.plus")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(PickemsColors.cardBackground)
                                        .foregroundStyle(theme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)

                            DynastySectionView()
                                .padding(.horizontal)

                            SocialShareCard(
                                group: group,
                                standings: appState.groupService.standings
                            )
                            .padding(.horizontal)

                            LeaderboardView()
                        }
                    }
                }
                .padding(.vertical)
            }
            .pickemsScreenBackground()
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HelpToolbarButton(topic: PickemsHelp.groupsOverview)
                }
            }
            .sheet(isPresented: $showCommissionerSettings) {
                if let group = appState.groupService.selectedGroup {
                    CommissionerSettingsView(group: group)
                }
            }
        }
    }

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

    private func groupHeader(_ group: PickemGroup) -> some View {
        VStack(spacing: 12) {
            PickemsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.name)
                        .font(.title2.bold())
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text("\(group.memberCount) members · Code: \(group.inviteCode)")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                InviteShareButton(group: group)
                    .accessibilityHint("Share your invite code with friends")

                ShareAppButton(leagueName: group.name, label: "Invite via X")
            }
            .padding(.horizontal)

            NavigationLink {
                MemberListView()
            } label: {
                Label("View Members", systemImage: "person.3")
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
            .padding(.horizontal)
        }
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
