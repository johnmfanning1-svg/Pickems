import SwiftUI

struct GroupsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var manageExpanded = false
    @State private var showLeaveConfirm = false
    @State private var leagueActionError: String?
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if appState.groupService.groups.isEmpty {
                        EmptyStateView(
                            icon: "trophy.fill",
                            title: "No Leagues Yet",
                            message: "Join or create a league to start competing.",
                            help: PickemsHelp.groupsOverview
                        )
                    } else {
                        groupPicker

                        if let group = appState.groupService.selectedGroup {
                            totalsHero(group)

                            LeaderboardView()

                            thisWeekCard(group)

                            primaryActions(group)

                            manageSection(group)

                            DynastySectionView()
                                .padding(.horizontal)

                            SocialShareCard(
                                group: group,
                                standings: appState.groupService.standings,
                                includeInviteCode: group.canShareInvite(
                                    asCommissioner: appState.isCommissioner
                                )
                            )
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .pickemsScreenBackground()
            .navigationTitle("Leagues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                HelpToolbarItem(topic: PickemsHelp.groupsOverview)
            }
            .pickemsRefreshable(isRefreshing: $isRefreshing) {
                await appState.refreshLeagueData()
            }
            .task(id: appState.groupService.selectedGroup?.id) {
                await appState.syncSelectedWeek()
            }
            .alert("Leave this league?", isPresented: $showLeaveConfirm) {
                Button("Leave League", role: .destructive) { leaveSelectedLeague() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You’ll lose access until you rejoin with the invite code.")
            }
            .onChange(of: appState.pendingCommissionerSettings) { _, pending in
                presentPendingCommissionerSettings(pending)
            }
            .onAppear {
                presentPendingCommissionerSettings(appState.pendingCommissionerSettings)
            }
        }
    }

    private func presentPendingCommissionerSettings(_ pending: Bool) {
        guard pending else { return }
        if appState.isCommissioner, appState.groupService.selectedGroup != nil {
            appState.present(.commissionerSettings)
        }
        appState.pendingCommissionerSettings = false
    }

    private func leaveSelectedLeague() {
        guard let group = appState.groupService.selectedGroup,
              let userId = appState.authService.currentUser?.id else { return }
        leagueActionError = nil
        Task {
            do {
                try await appState.groupService.leaveGroup(groupId: group.id, userId: userId)
                PickemsHaptics.success()
            } catch {
                leagueActionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
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
                            Task { await appState.syncSelectedWeek() }
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
                    Text(heroSubtitle(for: group))
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

    /// Members + week/slate context only — invite code lives on Invite/Share.
    private func heroSubtitle(for group: PickemGroup) -> String {
        var parts = ["\(group.memberCount) members"]
        if let week = appState.groupService.currentWeek {
            parts.append("Week \(week.weekNumber)")
            switch week.status {
            case .selection:
                parts.append(week.selectionMode.displayName)
            case .picking:
                parts.append("Pickems open")
            case .locked:
                parts.append("Pickems locked")
            case .scored:
                parts.append("Scored")
            }
        }
        return parts.joined(separator: " · ")
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

    // MARK: - This Week (pre-kickoff)

    @ViewBuilder
    private func thisWeekCard(_ group: PickemGroup) -> some View {
        if let week = appState.groupService.currentWeek,
           week.status == .selection || week.status == .picking {
            // Prefer live slate/nomination listeners over the week-doc counter.
            let uniqueGames = Set(
                appState.pickService.nominations.map(\.espnEventId)
                    + appState.pickService.slateGames.map(\.espnEventId)
            ).count
            let liveSlateCount = max(
                uniqueGames,
                appState.pickService.slateGames.count,
                week.nominationCount
            )
            let perMember = max(
                week.selectionsPerMember > 0 ? week.selectionsPerMember : group.rules.selectionsPerMember,
                1
            )
            let membersDone = appState.groupService.members.filter { member in
                appState.pickService.nominations.filter { $0.submittedBy == member.id }.count >= perMember
            }.count
            let targetSlate = group.rules.expectedSlateSize(memberCount: max(group.memberCount, 1))
            let statusCaption: String = {
                if week.status == .selection {
                    if group.rules.selectionMode == .member {
                        return "\(membersDone) of \(group.memberCount) done making Selections"
                    }
                    return "\(liveSlateCount)/\(targetSlate) slate"
                }
                let slateTotal = max(appState.pickService.slateGames.count, 1)
                let submittedCount = appState.groupService.members.filter { member in
                    if let sub = appState.pickService.submissions.first(where: { $0.userId == member.id }) {
                        if sub.isLocked { return true }
                        if sub.pickCount >= slateTotal { return true }
                    }
                    if let pick = appState.pickService.userPick, pick.userId == member.id {
                        if pick.isLocked { return true }
                        if pick.picks.count >= slateTotal { return true }
                    }
                    return false
                }.count
                return "\(submittedCount) of \(group.memberCount) submitted"
            }()

            PickemsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This Week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .accessibilityAddTraits(.isHeader)

                    Text(week.displayLabel)
                        .font(.headline)
                        .foregroundStyle(PickemsColors.textPrimary)

                    HStack(spacing: 16) {
                        if week.status == .selection, group.rules.selectionMode == .member {
                            Label(
                                "\(uniqueGames)/\(targetSlate) games",
                                systemImage: "american.football.fill"
                            )
                        } else if week.status == .selection {
                            Label(
                                "\(liveSlateCount)/\(targetSlate) slate",
                                systemImage: "american.football.fill"
                            )
                        } else {
                            Label(
                                "\(liveSlateCount) on slate",
                                systemImage: "american.football.fill"
                            )
                        }
                        Label(
                            statusCaption,
                            systemImage: "checkmark.circle"
                        )
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PickemsColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Primary actions

    private func primaryActions(_ group: PickemGroup) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

        return VStack(spacing: 12) {
            leaguePickemsEntry

            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink {
                    StatsView()
                } label: {
                    gridActionLabel("Stats", systemImage: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View your pick performance stats")

                NavigationLink {
                    MemberListView()
                } label: {
                    gridActionLabel("Members", systemImage: "person.3")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View league members and season records")

                GroupChatEntryButton(group: group)

                NavigationLink {
                    RivalryView()
                } label: {
                    gridActionLabel("Rivalry", systemImage: "person.2.fill")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Compare your record head-to-head with another member")
            }

            if group.canShareInvite(asCommissioner: appState.isCommissioner) {
                InviteShareButton(group: group)
                    .accessibilityHint("Share your invite code with friends")
            } else {
                CommissionerOnlyInviteNotice(
                    commissionerName: appState.groupService.members
                        .first { $0.id == group.commissionerId }?.displayName
                )
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var leaguePickemsEntry: some View {
        if let week = appState.groupService.currentWeek,
           WeekTransition.pickemsShouldShowLeagueBoard(week) {
            NavigationLink {
                LeaguePickemsEntryView()
            } label: {
                leaguePickemsCard(
                    subtitle: "Everyone's picks against the spread",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View League Pickems")
            .accessibilityHint("View this week's league Pickems chart")
        } else {
            leaguePickemsCountdownCard
        }
    }

    private func leaguePickemsCard(subtitle: String, showsChevron: Bool) -> some View {
        PickemsCard {
            HStack(spacing: 12) {
                Image(systemName: "person.3")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("View League Pickems")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.accent)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var leaguePickemsCountdownCard: some View {
        let week = appState.groupService.currentWeek
        return PickemsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "person.3")
                        .font(.title3)
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    Text("View League Pickems")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.accent)
                    Spacer(minLength: 0)
                }

                if let deadline = week?.pickDeadline {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PickDeadlineCalculator.countdownLabel(to: deadline))
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(PickemsColors.textPrimary)
                            Text("Locks \(PickDeadlineCalculator.lockTimeLabel(for: deadline))")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                    }
                } else if week?.status == .selection {
                    Text("Pickems lock after the slate is set. Everyone's picks show here after lock.")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Everyone's Pickems show here after they lock.")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("View League Pickems")
        .accessibilityHint("Countdown until Pickems lock. The league chart opens after lock.")
    }

    private func gridActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
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
                            appState.present(.commissionerSettings)
                        }
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
                        appState.present(.joinGroup)
                    }

                    manageRow(
                        title: "Create League",
                        systemImage: "plus.circle",
                        hint: "Start a brand new league you commission"
                    ) {
                        appState.present(.createLeague)
                    }

                    if group.canShareInvite(asCommissioner: appState.isCommissioner) {
                        ShareAppButton(leagueName: group.name, label: "Invite via X")
                    }

                    if !appState.isCommissioner {
                        manageRow(
                            title: "Leave League",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            hint: "Leave this league; you can rejoin with the invite code"
                        ) {
                            showLeaveConfirm = true
                        }
                    }

                    if let leagueActionError {
                        Text(leagueActionError)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
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
    static let previewLimit = 10

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var showWeekly = true

    private var allEntries: [StandingEntry] {
        appState.rankedStandings(weekly: showWeekly)
    }

    private var previewEntries: [StandingEntry] {
        Array(allEntries.prefix(Self.previewLimit))
    }

    private var rosterCount: Int {
        max(
            allEntries.count,
            appState.groupService.members.count,
            appState.groupService.selectedGroup?.memberCount ?? 0
        )
    }

    private var showsFullRanking: Bool {
        rosterCount > Self.previewLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Leaderboard",
                subtitle: showWeekly ? "This week's Pickem record" : "Season standings",
                help: PickemsHelp.leaderboard
            )

            Picker("Standings", selection: $showWeekly) {
                Text("This Week").tag(true)
                Text("Season").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityLabel("Standings period")

            if showsFullRanking {
                fullRankingLink
            }

            if allEntries.isEmpty {
                EmptyStateView(
                    icon: "chart.bar.fill",
                    title: "No Standings Yet",
                    message: "Invite members to see an interim ranking by join order.",
                    help: PickemsHelp.leaderboard
                )
            } else {
                ForEach(previewEntries) { entry in
                    LeaderboardRow(
                        entry: entry,
                        showWeekly: showWeekly,
                        isCommissioner: entry.id == appState.groupService.selectedGroup?.commissionerId
                    )
                    .padding(.horizontal)
                }
            }
        }
        .task(id: appState.groupService.currentWeek?.id) {
            guard let group = appState.groupService.selectedGroup,
                  let week = appState.groupService.currentWeek else { return }
            await appState.pickService.loadAllPicks(groupId: group.id, weekId: week.id)
        }
    }

    private var fullRankingLink: some View {
        NavigationLink {
            FullLeaderboardView(showWeekly: $showWeekly)
        } label: {
            PickemsCard {
                HStack(spacing: 12) {
                    Image(systemName: "list.number")
                        .font(.title3)
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full ranking")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accent)
                        Text("All \(rosterCount) members")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityLabel("View full ranking")
        .accessibilityHint("See every member in this league")
        .accessibilityValue("\(rosterCount) members")
    }
}

struct FullLeaderboardView: View {
    @Environment(AppState.self) private var appState
    @Binding var showWeekly: Bool

    private var entries: [StandingEntry] {
        appState.rankedStandings(weekly: showWeekly)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Standings", selection: $showWeekly) {
                    Text("This Week").tag(true)
                    Text("Season").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityLabel("Standings period")

                ForEach(entries) { entry in
                    LeaderboardRow(
                        entry: entry,
                        showWeekly: showWeekly,
                        isCommissioner: entry.id == appState.groupService.selectedGroup?.commissionerId
                    )
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
        }
        .pickemsScreenBackground()
        .navigationTitle("Full Ranking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            HelpToolbarItem(topic: PickemsHelp.leaderboard)
        }
    }
}
