import SwiftUI

/// League-scoped profile. Only people already on this league's roster or career list can be opened.
/// Team theme lives on `users/{uid}`, which other members cannot read, so the favorite-team row
/// is the signed-in member's own theme. Everyone else's stays off this screen.
struct LeagueMemberProfileView: View {
    let userId: String

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var snapshot = LeagueMemberProfilePolicy.Snapshot.empty
    @State private var isLoadingHistory = true
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if appState.groupService.selectedGroup == nil {
                EmptyStateView(
                    icon: "person.crop.circle",
                    title: "No league open",
                    message: "Open a league to see a member profile."
                )
            } else if !isSubject {
                EmptyStateView(
                    icon: "person.crop.circle.badge.xmark",
                    title: "Not in this league",
                    message: "Profiles stay inside the league you're in."
                )
            } else {
                profileScroll
            }
        }
        .pickemsScreenBackground()
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .pickemsRefreshable(isRefreshing: $isRefreshing) {
            await loadHistory()
        }
        .task(id: loadKey) {
            await loadHistory()
        }
    }

    private var profileScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PickemsSpacing.lg) {
                headerCard
                    .padding(.horizontal, PickemsSpacing.md)
                if isCurrentMember {
                    seasonSection
                } else {
                    formerMemberSeason
                }
                allTimeSection
                if let mostPicked = snapshot.mostPicked {
                    mostPickedSection(mostPicked)
                }
                if let headToHead = snapshot.headToHead, !isViewer, headToHead.weeksCompared > 0 {
                    headToHeadSection(headToHead)
                }
            }
            .padding(.vertical, PickemsSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        PickemsCard {
            VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
                HStack(alignment: .center, spacing: PickemsSpacing.sm) {
                    InitialsAvatar(
                        initials: initials,
                        colorHex: avatarColorHex,
                        imageURL: avatarImageURL,
                        size: 64
                    )
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayName)
                            .font(.title3.bold())
                            .foregroundStyle(PickemsColors.textPrimary)
                        if isCommissioner || coordinatorRole != nil || isViewer {
                            HStack(spacing: 6) {
                                if isCommissioner {
                                    commissionerChip
                                }
                                if let coordinatorRole {
                                    LeagueRoleBadge(role: coordinatorRole)
                                }
                                if isViewer {
                                    Text("This is you")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.08))
                                        .foregroundStyle(PickemsColors.textSecondary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                if isViewer {
                    viewerActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var viewerActions: some View {
        HStack(spacing: PickemsSpacing.sm) {
            Button {
                appState.present(.favoriteTeam(isOnboardingPrompt: false))
            } label: {
                favoriteTeamLabel
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the favorite team picker")

            Spacer(minLength: 8)

            Button("Settings") {
                appState.selectedTab = .profile
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.accent)
            .fixedSize()
            .accessibilityHint("Opens Settings")
        }
    }

    private var favoriteTeamLabel: some View {
        let team = appState.authService.currentUser?.favoriteTeam
        let palette = team.map { ThemePalette.from(team: $0) }
        return HStack(spacing: 10) {
            if let team, let url = URL(string: team.resolvedLogoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(palette?.accent ?? theme.accent)
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(team?.name ?? "Choose a team theme")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                    .lineLimit(1)
                Text(team?.abbreviation ?? "Colors for Pickems")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette?.accent ?? theme.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(team.map { "Team theme, \($0.name)" } ?? "Choose a team theme")
    }

    private var commissionerChip: some View {
        Text("Commissioner")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.accent.opacity(0.25))
            .foregroundStyle(theme.accent)
            .clipShape(Capsule())
            .accessibilityLabel("Commissioner")
    }

    // MARK: - This season

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            PickemsSectionHeader(title: "This season", subtitle: seasonSubtitle)
            PickemsCard {
                VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        statCell(title: "Rank", value: seasonRank.rankText)
                        statCell(title: "Record", value: seasonRecord)
                        if showsThisWeek {
                            statCell(title: "This week", value: weekRecord)
                        }
                        if showsWinningWeeks {
                            statCell(title: "Winning weeks", value: "\(snapshot.winningWeeks)")
                        }
                    }
                    if let champTitle = weekChampTitle {
                        Text(champTitle)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.2))
                            .foregroundStyle(theme.accent)
                            .clipShape(Capsule())
                    }
                    if let streakLabel = streakLabel {
                        Text(streakLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                    Text(battingLine)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, PickemsSpacing.md)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(seasonAccessibility)
        }
    }

    private var formerMemberSeason: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            PickemsSectionHeader(title: "This season", subtitle: group?.name)
            PickemsCard {
                Text("Not on this season's roster. Career numbers are below.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, PickemsSpacing.md)
        }
    }

    // MARK: - All-time

    private var allTimeSection: some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            PickemsSectionHeader(
                title: "All-time",
                subtitle: "Best weeks in this league"
            )
            PickemsCard {
                VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
                    if isLoadingHistory && snapshot.bestWeeks.isEmpty && !snapshot.failed {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                            .accessibilityLabel("Loading week history")
                    } else if snapshot.failed && snapshot.bestWeeks.isEmpty {
                        Text("Couldn't load week history. Season totals above are still current.")
                            .font(.subheadline)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if snapshot.bestWeeks.isEmpty {
                        Text("No scored weeks yet.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PickemsColors.textPrimary)
                        Text("Best weeks show up here after a week is scored.")
                            .font(.subheadline)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(snapshot.bestWeeks) { week in
                            HStack(alignment: .firstTextBaseline) {
                                Text(week.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(PickemsColors.textPrimary)
                                Spacer(minLength: 8)
                                Text(week.recordLabel)
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(PickemsColors.textPrimary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(week.label), \(week.recordLabel)")
                        }
                    }

                    if career.hasClosedHistory || joinedLine != nil || career.seasons > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                        if career.hasClosedHistory {
                            Text("Career \(career.recordLabel)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(PickemsColors.textPrimary)
                        }
                        Text(tenureLine)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, PickemsSpacing.md)
        }
    }

    private func mostPickedSection(_ team: LeagueMemberProfilePolicy.TeamTally) -> some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            PickemsSectionHeader(title: "Most picked", subtitle: "Locked and final picks")
            PickemsCard {
                HStack(spacing: 12) {
                    teamLogo(team.logoURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PickemsColors.textPrimary)
                        Text(team.abbreviation)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(team.count)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(PickemsColors.textPrimary)
                        Text(team.count == 1 ? "pick" : "picks")
                            .font(.caption2)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Most picked \(team.name), \(team.count) \(team.count == 1 ? "pick" : "picks")")
            }
            .padding(.horizontal, PickemsSpacing.md)
        }
    }

    private func headToHeadSection(_ headToHead: LeagueMemberProfilePolicy.HeadToHead) -> some View {
        VStack(alignment: .leading, spacing: PickemsSpacing.sm) {
            PickemsSectionHeader(title: "Vs you", subtitle: "Scored weeks, by who won the week")
            PickemsCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You \(headToHead.viewerWeekWins) · Them \(headToHead.memberWeekWins) · Ties \(headToHead.ties)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(PickemsColors.textPrimary)
                    Text("\(headToHead.weeksCompared) \(headToHead.weeksCompared == 1 ? "week" : "weeks")")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, PickemsSpacing.md)
        }
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(PickemsColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func teamLogo(_ urlString: String?) -> some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Image(systemName: "sportscourt")
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Facts

    private var group: PickemGroup? { appState.groupService.selectedGroup }

    private var isViewer: Bool { userId == appState.currentUserId }

    private var member: GroupMember? {
        guard appState.groupService.membersGroupId == group?.id else { return nil }
        return appState.groupService.members.first { $0.id == userId }
    }

    private var seasonEntry: StandingEntry? {
        appState.rankedStandings(weekly: false).first { $0.id == userId }
    }

    private var weekEntry: StandingEntry? {
        appState.rankedStandings(weekly: true).first { $0.id == userId }
    }

    private var careerRecord: CareerRecord? {
        appState.groupService.careerRecord(for: userId)
    }

    private var isSubject: Bool {
        guard let group else { return false }
        return LeagueMemberProfilePolicy.isLeagueSubject(
            userId: userId,
            memberIds: group.memberIds,
            careerIds: appState.groupService.careerRecords.map(\.id)
        )
    }

    private var isCurrentMember: Bool {
        group?.memberIds.contains(userId) == true
    }

    private var isCommissioner: Bool { group?.commissionerId == userId }

    private var coordinatorRole: LeagueCoordinatorRole? {
        group?.coordinatorRole(for: userId)
    }

    private var displayName: String {
        if let name = member?.displayName, !name.isEmpty { return name }
        if let name = seasonEntry?.displayName, !name.isEmpty { return name }
        if let name = careerRecord?.displayName, !name.isEmpty { return name }
        return "Member"
    }

    private var initials: String {
        if let member { return member.initials }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(2)).uppercased()
    }

    private var avatarColorHex: String {
        member?.avatarColorHex
            ?? seasonEntry?.avatarColorHex
            ?? careerRecord?.avatarColorHex
            ?? "#DC2626"
    }

    private var avatarImageURL: String? {
        if let url = member?.avatarImageURL, !url.isEmpty { return url }
        if let url = seasonEntry?.avatarImageURL, !url.isEmpty { return url }
        if isViewer { return appState.authService.currentUser?.avatarImageURL }
        return nil
    }

    private var seasonWins: Int { seasonEntry?.seasonWins ?? member?.seasonWins ?? 0 }
    private var seasonLosses: Int { seasonEntry?.seasonLosses ?? member?.seasonLosses ?? 0 }

    private var seasonRecord: String {
        LeagueMemberProfilePolicy.recordLabel(wins: seasonWins, losses: seasonLosses, pushes: 0)
    }

    private var weekWins: Int { weekEntry?.weeklyWins ?? 0 }
    private var weekLosses: Int { weekEntry?.weeklyLosses ?? 0 }

    private var showsThisWeek: Bool { weekWins + weekLosses > 0 }

    private var weekRecord: String {
        LeagueMemberProfilePolicy.recordLabel(wins: weekWins, losses: weekLosses, pushes: 0)
    }

    /// Same copy as Home: an em dash at 0–0, and `T-#` when the rank is shared.
    private var seasonRank: HomeLeagueStatus.Stat {
        HomeLeagueStatus.make(
            leagueName: group?.name ?? "",
            weekNumber: nil,
            weekStatus: nil,
            weeklyEntry: nil,
            weeklyBoard: [],
            seasonEntry: seasonEntry,
            seasonBoard: appState.rankedStandings(weekly: false)
        ).season
    }

    private var seasonSubtitle: String {
        group?.name ?? "This league"
    }

    private var showsWinningWeeks: Bool {
        !isLoadingHistory && !snapshot.bestWeeks.isEmpty
    }

    private var weekChampTitle: String? {
        guard let week = appState.groupService.currentWeek else { return nil }
        let entries = appState.rankedStandings(weekly: true).map {
            CelebrationPolicy.WeekBoardEntry(
                id: $0.id,
                rank: $0.rank,
                isTied: $0.isTied,
                weeklyWins: $0.weeklyWins,
                weeklyLosses: $0.weeklyLosses
            )
        }
        switch CelebrationPolicy.weekWinKind(entries: entries, userId: userId, weekStatus: week.status) {
        case .champ: return "Week Champ"
        case .coChamp: return "Week Co-Champ"
        case nil: return nil
        }
    }

    private var streakLabel: String? {
        let streak = snapshot.streak
        guard streak >= 2 else { return nil }
        if let badge = StreakEngine.badgeLabel(for: streak) { return badge }
        return "\(streak)-week streak"
    }

    private var battingLine: String {
        let average = BattingAverage.formatted(wins: seasonWins, losses: seasonLosses)
        if seasonWins + seasonLosses == 0 { return "No scored games yet" }
        return "Batting average \(average)"
    }

    private var career: LeagueMemberProfilePolicy.CareerTotals {
        LeagueMemberProfilePolicy.careerTotals(
            closed: careerRecord,
            currentWins: isCurrentMember ? seasonWins : 0,
            currentLosses: isCurrentMember ? seasonLosses : 0,
            isCurrentMember: isCurrentMember
        )
    }

    private var joinedLine: String? {
        guard let joined = member?.joinedAt else { return nil }
        return "Joined \(joined.formatted(date: .abbreviated, time: .omitted))"
    }

    private var tenureLine: String {
        var parts: [String] = []
        if career.seasons > 0 {
            parts.append("\(career.seasons) \(career.seasons == 1 ? "season" : "seasons")")
        }
        if career.titles > 0 {
            parts.append("\(career.titles) \(career.titles == 1 ? "title" : "titles")")
        }
        if let best = career.bestFinish {
            parts.append("Best finish #\(best)")
        }
        if let joinedLine {
            parts.append(joinedLine)
        }
        if parts.isEmpty { return "In this league" }
        return parts.joined(separator: " · ")
    }

    private var seasonAccessibility: String {
        var parts = ["\(displayName), \(seasonRank.accessibilityRank)"]
        parts.append("season \(seasonRecord)")
        if showsThisWeek { parts.append("this week \(weekRecord)") }
        if let weekChampTitle { parts.append(weekChampTitle) }
        if let streakLabel { parts.append(streakLabel) }
        return parts.joined(separator: ", ")
    }

    private var loadKey: String {
        "\(group?.id ?? "")|\(userId)"
    }

    private func loadHistory() async {
        guard let group, isSubject else {
            isLoadingHistory = false
            snapshot = .empty
            return
        }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        snapshot = await LeagueMemberProfileLoader.load(
            userId: userId,
            viewerId: appState.currentUserId,
            groupId: group.id,
            leaguePickMode: group.rules.pickMode,
            groupService: appState.groupService,
            pickService: appState.pickService
        )
    }
}
