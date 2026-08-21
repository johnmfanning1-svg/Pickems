import SwiftUI

struct GroupPicksView: View {
    var embedded: Bool = false
    var forceNominatingDisplay: Bool = false
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    /// Collapse-by-exception keeps sections default-open without seeding from async data.
    @State private var collapsedUserIds: Set<String> = []
    @State private var isRefreshingOwnPick = false
    @State private var ownPickLoadAttempted = false
    @State private var isRefreshing = false

    private var members: [GroupMember] {
        appState.groupService.members
    }

    private var week: WeekSummary? {
        appState.groupService.currentWeek
    }

    private var commissionerId: String? {
        appState.groupService.selectedGroup?.commissionerId
    }

    /// Building the slate (nominations / commissioner adds) — not spread-picking yet.
    private var isNominatingPhase: Bool {
        forceNominatingDisplay || week?.status == .selection
    }

    private var selectionMode: SelectionMode {
        appState.groupService.selectedGroup?.rules.selectionMode
            ?? week?.selectionMode
            ?? .member
    }

    /// Games each member must nominate during selection (member mode).
    private var nominationsPerMember: Int {
        max(
            week?.selectionsPerMember
                ?? appState.groupService.selectedGroup?.rules.selectionsPerMember
                ?? 1,
            1
        )
    }

    private var slateSize: Int {
        let memberCount = max(
            appState.groupService.selectedGroup?.memberCount ?? members.count,
            1
        )
        if isNominatingPhase, let rules = appState.groupService.selectedGroup?.rules {
            return rules.expectedSlateSize(memberCount: memberCount)
        }
        return max(slateGames.count, 1)
    }

    /// Materialized slate for spread picks. Do **not** fall back to nominations —
    /// that made 1 nomination look like a 1-game pick slate (0/1, 1 left).
    private var slateGames: [SlateGame] {
        appState.pickService.slateGames
    }

    private var nominations: [Nomination] {
        appState.pickService.nominations
    }

    /// Prefer `allPicks`, but always surface the signed-in member's `userPick` pre-deadline.
    private var picksByUserId: [String: UserPick] {
        var map = Dictionary(uniqueKeysWithValues: appState.pickService.allPicks.map { ($0.userId, $0) })
        if let own = appState.pickService.userPick {
            map[own.userId] = own
        }
        return map
    }

    private var doneUserIds: Set<String> {
        Set(members.map(\.id).filter(isDone))
    }

    private var picksVisibleToAll: Bool {
        guard let week else { return false }
        if week.status == .locked || week.status == .scored { return true }
        return ScoringEngine.isPastDeadline(deadline: week.pickDeadline)
    }

    private var currentUserId: String? {
        appState.authService.currentUser?.id ?? appState.authService.currentUserId
    }

    private var sortedMembers: [GroupMember] {
        members.sorted { lhs, rhs in
            let leftIsComm = lhs.id == commissionerId
            let rightIsComm = rhs.id == commissionerId
            if leftIsComm != rightIsComm { return leftIsComm && !rightIsComm }
            let leftDone = isDone(lhs.id)
            let rightDone = isDone(rhs.id)
            if leftDone != rightDone { return leftDone && !rightDone }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if embedded {
                innerList
            } else {
                ScrollView {
                    innerList
                }
            }
        }
        .modifier(ConditionalNavTitle(
            enabled: !embedded,
            title: isNominatingPhase ? "League Selections" : "League Pickems"
        ))
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .task(id: "\(appState.groupService.selectedGroup?.id ?? "")-\(week?.id ?? "")-\(week?.status.rawValue ?? "")") {
            await appState.syncSelectedWeek()
            await refreshAllPicks()
            await appState.picksViewModel.ensureTeamRanks(appState: appState)
            if showsPickemsBoard, let week {
                appState.picksViewModel.startLiveRefresh(week: week, appState: appState)
            }
        }
        .onChange(of: appState.pickService.userPick) { _, newPick in
            appState.pickService.mergeOwnPickIntoAllPicks(newPick)
        }
        .modifier(OptionalTabRefresh(
            enabled: !embedded,
            isRefreshing: $isRefreshing
        ) {
            await appState.refreshLeagueData()
            await refreshAllPicks()
        })
    }

    private var innerList: some View {
        VStack(spacing: 12) {
            progressCard

            if sortedMembers.isEmpty {
                ContentUnavailableView(
                    "No Members",
                    systemImage: "person.3",
                    description: Text("League members will appear here.")
                )
                .padding(.top, 24)
            } else if showsPickemsBoard {
                LeaguePickemsBoard(
                    members: sortedMembers,
                    games: slateGames.sortedByKickoff,
                    picksByUserId: picksByUserId,
                    liveCards: appState.picksViewModel.livePickCards,
                    teamRanks: appState.picksViewModel.teamRanks,
                    currentUserId: currentUserId
                )
            } else {
                ForEach(sortedMembers) { member in
                    memberSection(member)
                }
            }
        }
        .padding(embedded ? 0 : 16)
        .padding(.horizontal, embedded ? 16 : 0)
    }

    // MARK: - Progress

    private var progressCard: some View {
        PickemsCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progressTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PickemsColors.textPrimary)
                    Spacer()
                    Text(progressTrailing)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                Text(progressSubtitle)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                if isNominatingPhase,
                   appState.isCommissioner,
                   selectionMode == .member,
                   week.map({ WeekTransition.commissionerCanManageSelections($0) }) ?? false {
                    Text("Expand a member to remove, replace, or add their Selections.")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
            }
        }
    }

    private var progressTitle: String {
        if isNominatingPhase {
            return "\(doneUserIds.count) of \(members.count) done making Selections"
        }
        return "\(doneUserIds.count) of \(members.count) submitted"
    }

    private var progressTrailing: String {
        if isNominatingPhase {
            return "\(nominations.count)/\(slateSize) on slate"
        }
        return "\(slateGames.count) games"
    }

    private var progressSubtitle: String {
        if isNominatingPhase {
            if selectionMode == .member {
                return "Each member selects \(nominationsPerMember) game\(nominationsPerMember == 1 ? "" : "s"). Pickems open when the slate fills."
            }
            return "Commissioner is building a \(slateSize)-game slate. Pickems open when it’s ready."
        }
        if slateGames.isEmpty {
            return "No slate games yet."
        }
        if showsPickemsBoard {
            return "Games as rows, members as columns. Colors update as games go."
        }
        return "Make a Pickem against the spread for every game on the slate."
    }

    private var showsPickemsBoard: Bool {
        !isNominatingPhase && picksVisibleToAll && !slateGames.isEmpty
    }

    // MARK: - Member section

    @ViewBuilder
    private func memberSection(_ member: GroupMember) -> some View {
        let isCollapsed = collapsedUserIds.contains(member.id)
        let pick = picksByUserId[member.id]
        let done = isDone(member.id)
        let total = expectedTotal(for: member.id)
        let made = madeCount(for: member.id, pick: pick)
        let remaining = max(total - made, 0)
        let isComm = member.id == commissionerId

        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedUserIds.remove(member.id)
                    } else {
                        collapsedUserIds.insert(member.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    InitialsAvatar(
                        initials: member.initials,
                        colorHex: member.avatarColorHex,
                        imageURL: member.avatarImageURL
                            ?? (member.id == currentUserId ? appState.authService.currentUser?.avatarImageURL : nil),
                        size: 32
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(member.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PickemsColors.textPrimary)
                            if isComm {
                                Image(systemName: "gavel")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.accent)
                                    .accessibilityLabel("Commissioner")
                            }
                        }
                        HStack(spacing: 8) {
                            Text("\(made)/\(total)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PickemsColors.textSecondary)
                            if remaining > 0, total > 0, !done {
                                Text("\(remaining) left")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(PickemsColors.warning)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    StatusBadge(
                        text: statusLabel(done: done),
                        color: done ? PickemsColors.success : PickemsColors.warning
                    )

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
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
            .accessibilityHint(isCollapsed ? "Show details" : "Hide details")
            .accessibilityAddTraits(.isButton)
            if !isCollapsed {
                VStack(spacing: 8) {
                    memberBody(member: member, pick: pick, done: done)
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func memberBody(member: GroupMember, pick: UserPick?, done: Bool) -> some View {
        if isNominatingPhase {
            nominationBody(for: member)
        } else if !picksVisibleToAll, !canRevealPickDetails(for: member.id) {
            if done {
                Text("Pickems hidden until the deadline")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
            } else {
                emptyPicksState(title: "No Pickems yet", message: "\(member.displayName) hasn't submitted.")
            }
        } else if canRevealPickDetails(for: member.id),
                  done,
                  pick == nil || pick?.picks.isEmpty == true,
                  isRefreshingOwnPick || !ownPickLoadAttempted {
            ownPickPendingState
        } else {
            pickemsBody(pick: pick)
        }
    }

    /// Slate Selections stay visible even when Pickems are cleared.
    @ViewBuilder
    private func pickemsBody(pick: UserPick?) -> some View {
        if slateGames.isEmpty {
            emptyPicksState(title: "No slate yet", message: "Selections will show here once the slate is built.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Selections stay on the slate. A dash means no Pickem yet.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .padding(.horizontal, 10)
                ForEach(slateGames) { game in
                    PickResultRow(
                        game: game,
                        pickedTeamId: pick?.picks[game.id],
                        showSpread: true,
                        homeRank: appState.picksViewModel.teamRanks.rank(for: game.homeTeamId),
                        awayRank: appState.picksViewModel.teamRanks.rank(for: game.awayTeamId)
                    )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    @ViewBuilder
    private func nominationBody(for member: GroupMember) -> some View {
        let noms = nominations.filter { $0.submittedBy == member.id }
        let canRemake = week.map { WeekTransition.canRemakeSelections($0) } ?? false
        let isOwn = member.id == currentUserId
        let commissionerCanManage = appState.isCommissioner
            && (week.map { WeekTransition.commissionerCanManageSelections($0) } ?? false)
        let memberCanRemove = canRemake && isOwn && !appState.pickService.didSubmitNominations
        let canRemove = memberCanRemove || commissionerCanManage
        let canAdd = commissionerCanManage && noms.count < nominationsPerMember
            && selectionMode == .member

        VStack(alignment: .leading, spacing: 8) {
            if isOwn, canRemake {
                Text("This list is Selections (the games). Remove Selection frees a slot. Pickems (who covers) start after the slate opens.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .padding(.horizontal, 6)
            }
            if isOwn, canRemake, appState.pickService.didSubmitNominations {
                SecondaryButton("Edit Selections", icon: "pencil") {
                    appState.picksViewModel.unlockSelectionsForEditing(appState: appState)
                }
                .padding(.horizontal, 6)
            }

            if noms.isEmpty {
                emptyPicksState(
                    title: "No Selections yet",
                    message: "\(member.displayName) still needs to select \(nominationsPerMember) game\(nominationsPerMember == 1 ? "" : "s")."
                )
            } else {
                ForEach(noms) { nom in
                    PickemsCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(nominationMatchupLabel(nom))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(PickemsColors.textPrimary)
                                Text(nominationSpreadLabel(nom))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.accent)
                            }
                            Spacer(minLength: 8)
                            if canRemove, let rules = appState.groupService.selectedGroup?.rules {
                                if commissionerCanManage {
                                    Button {
                                        appState.picksViewModel.beginReplaceSelection(nom, appState: appState)
                                    } label: {
                                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(theme.accent)
                                    }
                                    .accessibilityHint("Pick a different game for \(member.displayName)")
                                }
                                Button(role: .destructive) {
                                    appState.picksViewModel.removeNomination(nom, rules: rules, appState: appState)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(theme.accent)
                                }
                                .accessibilityHint("Frees a slot so a different game can be selected")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 4)
                }
            }

            if canAdd {
                SecondaryButton("Add Selection", icon: "plus") {
                    appState.picksViewModel.beginAddSelection(for: member, appState: appState)
                }
                .padding(.horizontal, 6)
            }
        }
    }

    private func nominationMatchupLabel(_ nom: Nomination) -> String {
        let away = nom.awayTeamAbbreviation ?? String(nom.awayTeamName.prefix(4))
        let home = nom.homeTeamAbbreviation ?? String(nom.homeTeamName.prefix(4))
        let ranks = appState.picksViewModel.teamRanks
        return TeamDisplay.matchupLabel(
            awayAbbreviation: away,
            awayRank: nom.awayTeamId.flatMap { ranks.rank(for: $0) },
            homeAbbreviation: home,
            homeRank: nom.homeTeamId.flatMap { ranks.rank(for: $0) }
        )
    }

    private func nominationSpreadLabel(_ nom: Nomination) -> String {
        let abbr: String
        if nom.spreadTeamId == nom.homeTeamId {
            abbr = nom.homeTeamAbbreviation ?? String(nom.homeTeamName.prefix(4)).uppercased()
        } else if nom.spreadTeamId == nom.awayTeamId {
            abbr = nom.awayTeamAbbreviation ?? String(nom.awayTeamName.prefix(4)).uppercased()
        } else {
            abbr = "FAV"
        }
        return String(format: "%@ %g", abbr, -abs(nom.spread))
    }

    private var ownPickPendingState: some View {
        VStack(spacing: 10) {
            if isRefreshingOwnPick || !ownPickLoadAttempted {
                ProgressView()
                Text("Loading your Pickems…")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
            } else {
                Text("Couldn't load your Pickems")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text("Try again to show your submitted Pickems.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                Button("Retry") {
                    Task { await refreshAllPicks() }
                }
                .buttonStyle(.bordered)
                .tint(PickemsColors.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
    }

    private func emptyPicksState(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Helpers

    private func refreshAllPicks() async {
        guard let group = appState.groupService.selectedGroup,
              let week else { return }
        isRefreshingOwnPick = true
        defer {
            isRefreshingOwnPick = false
            ownPickLoadAttempted = true
        }
        await appState.pickService.loadAllPicks(groupId: group.id, weekId: week.id)
        appState.pickService.mergeOwnPickIntoAllPicks(appState.pickService.userPick)
    }

    private func submission(for userId: String) -> PickSubmission? {
        appState.pickService.submissions.first { $0.userId == userId }
    }

    private func expectedTotal(for userId: String) -> Int {
        if isNominatingPhase {
            if selectionMode == .member {
                return nominationsPerMember
            }
            // Commissioner-built slate: members don't nominate; show slate fill for commissioner only.
            return userId == commissionerId ? slateSize : 0
        }
        return max(slateGames.count, 1)
    }

    private func madeCount(for userId: String, pick: UserPick?) -> Int {
        if isNominatingPhase {
            if selectionMode == .member {
                return nominations.filter { $0.submittedBy == userId }.count
            }
            if userId == commissionerId {
                return slateGames.count
            }
            return 0
        }

        let fromPick = pick?.picks.count ?? 0
        let fromSub = submission(for: userId)?.pickCount ?? 0
        let total = slateGames.count
        if isLockedIn(userId), max(fromPick, fromSub) == 0, total > 0 {
            return total
        }
        return max(fromPick, fromSub)
    }

    private func isDone(_ userId: String) -> Bool {
        if isNominatingPhase, selectionMode == .commissioner, userId != commissionerId {
            return true
        }
        let total = expectedTotal(for: userId)
        if total == 0 { return false }
        if isNominatingPhase {
            return madeCount(for: userId, pick: nil) >= total
        }
        if isLockedIn(userId) { return true }
        return madeCount(for: userId, pick: picksByUserId[userId]) >= total
    }

    private func isLockedIn(_ userId: String) -> Bool {
        if picksByUserId[userId]?.isLocked == true { return true }
        return submission(for: userId)?.isLocked == true
    }

    private func statusLabel(done: Bool) -> String {
        if isNominatingPhase {
            return done ? "Selected" : "Selecting"
        }
        return done ? "Submitted" : "In progress"
    }

    private func canRevealPickDetails(for userId: String) -> Bool {
        userId == currentUserId || appState.isCommissioner
    }
}

private struct OptionalTabRefresh: ViewModifier {
    let enabled: Bool
    @Binding var isRefreshing: Bool
    let action: () async -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.pickemsRefreshable(isRefreshing: $isRefreshing, action: action)
        } else {
            content
        }
    }
}

private struct ConditionalNavTitle: ViewModifier {
    let enabled: Bool
    let title: String

    func body(content: Content) -> some View {
        if enabled {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
