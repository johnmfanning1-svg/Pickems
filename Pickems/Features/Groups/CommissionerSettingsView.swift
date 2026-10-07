import SwiftUI

struct CommissionerSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    let group: PickemGroup
    @State private var rules: GroupRules
    @State private var isPublic: Bool
    @State private var commissionerOnlyInvites: Bool
    @State private var groupName: String
    @State private var isSaving = false
    @State private var showCloseSeasonConfirm = false
    @State private var closeSeasonError: String?

    @State private var isEditingCode = false
    @State private var customCode = ""
    @State private var isUpdatingCode = false
    @State private var identityError: String?
    @State private var memberToRemove: GroupMember?
    @State private var memberActionError: String?
    @State private var memberToPromote: GroupMember?
    @State private var showDeleteLeagueConfirm = false
    @State private var isWorkingMembers = false
    @State private var showSelectionDeadlineSheet = false
    @State private var showPickDeadlineSheet = false
    @State private var showAdminGameBrowse = false
    @State private var isSwitchingToRolling = false
    @State private var rollingPromptWeek: WeekSummary?
    @State private var rollingStatus: String?
    @State private var rollingError: String?

    @FocusState private var codeFieldFocused: Bool

    init(group: PickemGroup) {
        self.group = group
        _rules = State(initialValue: group.rules)
        _isPublic = State(initialValue: group.isPublic)
        _commissionerOnlyInvites = State(initialValue: group.commissionerOnlyInvites == true)
        _groupName = State(initialValue: group.name)
    }

    private var liveGroup: PickemGroup {
        appState.groupService.selectedGroup?.id == group.id
            ? (appState.groupService.selectedGroup ?? group)
            : group
    }

    private var otherMembers: [GroupMember] {
        appState.groupService.members
            .filter { $0.id != liveGroup.commissionerId }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var seasonYearToClose: Int {
        appState.groupService.cfbWeek?.seasonYear
            ?? appState.groupService.currentWeek?.seasonYear
            ?? Calendar.current.component(.year, from: Date())
    }

    private var seasonAlreadyClosed: Bool {
        appState.groupService.seasonArchives.contains { $0.seasonYear == seasonYearToClose }
    }

    private var visibilityFooter: String {
        if isPublic {
            return "Public leagues appear in Discover. See who's in is on the Pickems tab."
        }
        return "Private leagues stay off Discover. Turn on Only commissioner can invite to hide Invite Friends for members — they will be asked to contact you instead. You still share the code from Invite Friends on the Leagues tab."
    }

    // `body` is split into small pieces on purpose: as one expression (every section,
    // alert and sheet inline) it hit "unable to type-check this expression in
    // reasonable time" in Release archives after the rolling-lock section landed.
    var body: some View {
        NavigationStack {
            settingsFormWithSheets
        }
    }

    // MARK: - Form

    private var settingsForm: some View {
        Form {
            CommissionerWeekAdminSections(
                showSelectionDeadlineSheet: $showSelectionDeadlineSheet,
                showPickDeadlineSheet: $showPickDeadlineSheet,
                showAdminGameBrowse: $showAdminGameBrowse
            )
            leagueIdentitySection
            membersSection
            scoringSection
            slateConfigurationSection
            pickemsLockSection
            tiesSection
            visibilitySection
            dynastySection
        }
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .navigationTitle("Commissioner Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { settingsToolbar }
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }
                .fontWeight(.semibold)
                .disabled(isSaving)
        }
    }

    private var scoringSection: some View {
        Section {
            LabeledContent("League type", value: rules.pickMode.displayName)
                .listRowBackground(PickemsColors.cardBackground)
        } header: {
            Text("Scoring")
        } footer: {
            Text("ATS grades the cover. Straight Up grades the outright winner (a tie is a push). League type is set at create. In an ATS league, use This Week to score a future week — or the current week before lock — Straight Up.")
        }
    }

    private var slateConfigurationFooter: String {
        rules.selectionMode == .member
            ? "Each member selects this many games. Weekly game target = members × Selections. You’ll set a Selection deadline each week."
            : "You choose every game for the group each week."
    }

    private var slateConfigurationSection: some View {
        Section {
            Picker("Who selects games", selection: $rules.selectionMode) {
                ForEach(SelectionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .listRowBackground(PickemsColors.cardBackground)

            if rules.selectionMode == .member {
                Stepper(
                    "Selections per member: \(rules.selectionsPerMember)",
                    value: $rules.selectionsPerMember,
                    in: 1...10
                )
                .listRowBackground(PickemsColors.cardBackground)
            } else {
                Stepper("Games per week: \(rules.slateSize)", value: $rules.slateSize, in: 1...20)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            sectionHeader("Slate Configuration", help: PickemsHelp.commissionerSettings)
        } footer: {
            Text(slateConfigurationFooter)
        }
    }

    // MARK: - Pickems Lock

    private var pickemsLockSection: some View {
        Section {
            lockModeRows
            rollingFeedbackRows
            latePickRows
        } header: {
            sectionHeader("Pickems Lock", help: PickemsHelp.pickDeadline)
        } footer: {
            Text(pickemsLockFooter)
        }
    }

    /// Rolling leagues keep the Lock mode picker; first-kickoff leagues get the
    /// Switch to Rolling Lock action (the server-side `setRollingLock` callable).
    @ViewBuilder
    private var lockModeRows: some View {
        if liveGroup.rules.pickDeadline.isRolling {
            Picker("Lock mode", selection: lockModeBinding) {
                ForEach(DeadlinePolicy.lockModeCases) { (mode: DeadlinePolicy) in
                    Text(mode.lockModeDisplayName).tag(mode)
                }
            }
            .listRowBackground(PickemsColors.cardBackground)
        } else {
            LabeledContent("Lock mode", value: DeadlinePolicy.firstKickoff.lockModeDisplayName)
                .listRowBackground(PickemsColors.cardBackground)

            switchToRollingButton
        }
    }

    private var switchToRollingButton: some View {
        Button {
            beginRollingSwitch()
        } label: {
            switchToRollingLabel
        }
        .buttonStyle(.borderless)
        .foregroundStyle(theme.accent)
        .disabled(isSwitchingToRolling)
        .listRowBackground(PickemsColors.cardBackground)
    }

    @ViewBuilder
    private var switchToRollingLabel: some View {
        if isSwitchingToRolling {
            HStack { ProgressView(); Text("Switching to rolling lock…") }
        } else {
            Label(RollingLockSwitch.buttonTitle, systemImage: "clock.arrow.circlepath")
        }
    }

    @ViewBuilder
    private var rollingFeedbackRows: some View {
        if let rollingStatus {
            Text(rollingStatus)
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
                .listRowBackground(PickemsColors.cardBackground)
        }
        if let rollingError {
            Text(rollingError)
                .font(.caption)
                .foregroundStyle(PickemsColors.warning)
                .listRowBackground(PickemsColors.cardBackground)
        }
    }

    @ViewBuilder
    private var latePickRows: some View {
        if rules.pickDeadline != .rolling {
            Toggle("Allow late Pickems", isOn: $rules.allowLatePicks)
                .listRowBackground(PickemsColors.cardBackground)
            if rules.allowLatePicks {
                Stepper(
                    "Late penalty: \(rules.latePickPenaltyWins) win(s)",
                    value: $rules.latePickPenaltyWins,
                    in: 1...3
                )
                .listRowBackground(PickemsColors.cardBackground)
            }
        }
    }

    // MARK: - Ties / Visibility / Dynasty

    private var tiesSection: some View {
        Section {
            Picker("Tie breaker", selection: $rules.tieBreaker) {
                ForEach(TieBreakerPolicy.allCases) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .listRowBackground(PickemsColors.cardBackground)

            Toggle("Confidence pick (2x one game)", isOn: $rules.allowConfidencePick)
                .listRowBackground(PickemsColors.cardBackground)
        } header: {
            sectionHeader("Ties", help: PickemsHelp.tieBreaker)
        } footer: {
            Text("Commissioner Override lets you rank equal records after this week is scored. Head-to-Head uses this week’s slate automatically.")
        }
    }

    private var visibilitySection: some View {
        Section {
            Toggle("List in Discover", isOn: $isPublic)
                .listRowBackground(PickemsColors.cardBackground)
            if !isPublic {
                Toggle("Only commissioner can invite", isOn: $commissionerOnlyInvites)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("Visibility")
        } footer: {
            Text(visibilityFooter)
        }
    }

    private var dynastySection: some View {
        Section {
            closeSeasonRow

            if let closeSeasonError {
                Text(closeSeasonError)
                    .font(.caption)
                    .foregroundStyle(theme.accent)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("Dynasty")
        } footer: {
            Text("Archives final standings and resets season W–L. Auto-close also runs mid-January via Cloud Functions.")
        }
    }

    @ViewBuilder
    private var closeSeasonRow: some View {
        if seasonAlreadyClosed {
            LabeledContent("Season \(seasonYearToClose.pickemsYearString)", value: "Archived")
                .listRowBackground(PickemsColors.cardBackground)
        } else {
            Button(role: .destructive) {
                showCloseSeasonConfirm = true
            } label: {
                closeSeasonButtonLabel
            }
            .disabled(appState.groupService.isClosingSeason)
            .listRowBackground(PickemsColors.cardBackground)
        }
    }

    @ViewBuilder
    private var closeSeasonButtonLabel: some View {
        let yearString: String = seasonYearToClose.pickemsYearString
        if appState.groupService.isClosingSeason {
            HStack {
                ProgressView()
                Text("Closing Season \(yearString)…")
            }
        } else {
            Label("Close Season \(yearString)", systemImage: "trophy.fill")
        }
    }

    // MARK: - Alerts

    private var rollingPromptPresented: Binding<Bool> {
        Binding<Bool>(
            get: { rollingPromptWeek != nil },
            set: { (isPresented: Bool) in if !isPresented { rollingPromptWeek = nil } }
        )
    }

    private var memberToRemovePresented: Binding<Bool> {
        Binding<Bool>(
            get: { memberToRemove != nil },
            set: { (isPresented: Bool) in if !isPresented { memberToRemove = nil } }
        )
    }

    private var memberToPromotePresented: Binding<Bool> {
        Binding<Bool>(
            get: { memberToPromote != nil },
            set: { (isPresented: Bool) in if !isPresented { memberToPromote = nil } }
        )
    }

    private var removeMemberAlertTitle: String {
        "Remove \(memberToRemove?.displayName ?? "member")?"
    }

    private var promoteMemberAlertTitle: String {
        "Make \(memberToPromote?.displayName ?? "member") the commissioner?"
    }

    private var closeSeasonAlertTitle: String {
        "Close Season \(seasonYearToClose.pickemsYearString)?"
    }

    /// Rolling-lock prompt + Close Season confirm.
    private var settingsFormWithSeasonAlerts: some View {
        settingsForm
            .alert(
                RollingLockSwitch.promptTitle,
                isPresented: rollingPromptPresented,
                presenting: rollingPromptWeek
            ) { (week: WeekSummary) in
                Button(RollingLockSwitch.applyNowTitle) {
                    performRollingSwitch(applyTo: week)
                }
                Button(RollingLockSwitch.nextWeekTitle) {
                    performRollingSwitch(applyTo: nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: { (_: WeekSummary) in
                Text(RollingLockSwitch.promptMessage)
            }
            .alert(closeSeasonAlertTitle, isPresented: $showCloseSeasonConfirm) {
                Button("Close Season", role: .destructive) { closeSeason() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This archives \(seasonYearToClose.pickemsYearString) standings and resets everyone’s season record. This cannot be undone.")
            }
    }

    /// Remove member, transfer commissioner and delete league confirms.
    private var settingsFormWithAlerts: some View {
        settingsFormWithSeasonAlerts
            .alert(removeMemberAlertTitle, isPresented: memberToRemovePresented) {
                Button("Remove Member", role: .destructive) {
                    if let member = memberToRemove { removeMember(member) }
                    memberToRemove = nil
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            } message: {
                Text("They lose access to this league’s picks and standings. They can rejoin with the invite code.")
            }
            .alert(promoteMemberAlertTitle, isPresented: memberToPromotePresented) {
                Button("Transfer Commissioner", role: .destructive) {
                    if let member = memberToPromote { transferCommissioner(to: member) }
                    memberToPromote = nil
                }
                Button("Cancel", role: .cancel) { memberToPromote = nil }
            } message: {
                Text("You become a regular member. Only one commissioner is allowed at a time.")
            }
            .alert("Delete this league permanently?", isPresented: $showDeleteLeagueConfirm) {
                Button("Delete League", role: .destructive) { deleteLeague() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the league, invite code, members, picks, standings, and season history for everyone. This cannot be undone.")
            }
    }

    // MARK: - Sheets

    private var spreadEditGameBinding: Binding<SlateGame?> {
        Binding<SlateGame?>(
            get: { appState.picksViewModel.spreadEditGame },
            set: { appState.picksViewModel.spreadEditGame = $0 }
        )
    }

    private var settingsFormWithSheets: some View {
        settingsFormWithAlerts
            .sheet(isPresented: $showSelectionDeadlineSheet) {
                selectionDeadlineSheet
            }
            .sheet(isPresented: $showPickDeadlineSheet) {
                pickDeadlineSheet
            }
            .sheet(isPresented: $showAdminGameBrowse) {
                adminGameBrowseSheet
            }
            .sheet(item: spreadEditGameBinding) { (game: SlateGame) in
                spreadEditorSheet(for: game)
            }
    }

    private var selectionDeadlineSheet: some View {
        SelectionDeadlineSheet(
            weekLabel: appState.groupService.currentWeek?.displayLabel ?? "This week",
            initialDeadline: appState.groupService.currentWeek?.selectionDeadline
        ) { deadline in
            appState.picksViewModel.setSelectionDeadline(deadline, appState: appState)
        }
        .pickemsEnvironment(appState)
    }

    @ViewBuilder
    private var pickDeadlineSheet: some View {
        if let week = appState.groupService.currentWeek {
            pickDeadlineEditor(for: week)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "No Active Week",
                    systemImage: "calendar",
                    description: Text("Open Commissioner Settings again after a week is selected.")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showPickDeadlineSheet = false }
                    }
                }
            }
            .pickemsEnvironment(appState)
        }
    }

    private func pickDeadlineEditor(for week: WeekSummary) -> some View {
        let initialDeadline: Date? = week.isRollingLock
            ? (week.remainingLockAt ?? week.effectiveWeekLockAt ?? week.pickDeadline)
            : week.pickDeadline
        return PickDeadlineEditorSheet(
            weekLabel: week.displayLabel,
            weekStatus: week.status,
            initialDeadline: initialDeadline,
            isPastDeadline: WeekTransition.arePicksFullyLocked(week),
            isRollingLock: week.isRollingLock,
            onLockRemainingNow: {
                appState.picksViewModel.lockRemainingGamesNow(appState: appState)
            }
        ) { deadline, reopen, unlock in
            appState.picksViewModel.setPickDeadline(
                deadline,
                reopenWeek: reopen,
                unlockMemberPicks: unlock,
                appState: appState
            )
        }
        .pickemsEnvironment(appState)
    }

    private var adminGameBrowseSheet: some View {
        GameBrowseView(
            seedGames: appState.picksViewModel.espnGames
        ) { games in
            try await appState.picksViewModel.saveBrowseSelections(games, appState: appState)
        }
        .pickemsEnvironment(appState)
    }

    private func spreadEditorSheet(for game: SlateGame) -> some View {
        SpreadEditorSheet(game: game) { spread, spreadTeamId in
            appState.picksViewModel.updateSpread(
                game,
                spread: spread,
                spreadTeamId: spreadTeamId,
                appState: appState
            )
        }
        .pickemsEnvironment(appState)
    }

    private var leagueIdentitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("League name")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                TextField("League name", text: $groupName)
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(PickemsColors.textPrimary)
            }
            .listRowBackground(PickemsColors.cardBackground)

            if isEditingCode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite code")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                    TextField("ABCD12", text: $customCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($codeFieldFocused)
                        .onChange(of: customCode) { _, newValue in
                            customCode = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
                        }
                        .foregroundStyle(PickemsColors.textPrimary)
                    HStack {
                        Button("Save Code") { saveCustomCode() }
                            .buttonStyle(.borderless)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.accent)
                            .disabled(isUpdatingCode || customCode.count < 4)
                        Spacer()
                        Button("Cancel") {
                            isEditingCode = false
                            codeFieldFocused = false
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(PickemsColors.textSecondary)
                    }
                    Text("4–8 letters or numbers. Members join with this code.")
                        .font(.caption2)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .listRowBackground(PickemsColors.cardBackground)
            } else {
                LabeledContent("Invite code", value: liveGroup.inviteCode)
                    .listRowBackground(PickemsColors.cardBackground)

                Button {
                    customCode = liveGroup.inviteCode
                    isEditingCode = true
                    codeFieldFocused = true
                } label: {
                    Label("Set Custom Code", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.accent)
                .listRowBackground(PickemsColors.cardBackground)

                Button {
                    regenerateCode()
                } label: {
                    if isUpdatingCode {
                        HStack { ProgressView(); Text("Rolling new code…") }
                    } else {
                        Label("Regenerate Code", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.accent)
                .disabled(isUpdatingCode)
                .listRowBackground(PickemsColors.cardBackground)
            }

            if let identityError {
                Text(identityError)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.warning)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("League Identity")
        } footer: {
            Text("Rename the league or change the invite code any time. The old code stops working once you change it.")
        }
    }

    @ViewBuilder
    private var membersSection: some View {
        Section {
            if otherMembers.isEmpty {
                Text("No other members yet. Share your invite code to grow the league.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .listRowBackground(PickemsColors.cardBackground)
            } else {
                ForEach(otherMembers) { member in
                    HStack(spacing: 12) {
                        InitialsAvatar(
                            initials: member.initials,
                            colorHex: member.avatarColorHex,
                            imageURL: member.avatarImageURL,
                            size: 36
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .foregroundStyle(PickemsColors.textPrimary)
                            Text("\(member.seasonWins)-\(member.seasonLosses) this season")
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                        Spacer()
                        Button {
                            memberToPromote = member
                        } label: {
                            Image(systemName: "gavel")
                                .foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Make \(member.displayName) commissioner")
                        .disabled(isWorkingMembers)

                        Button(role: .destructive) {
                            memberToRemove = member
                        } label: {
                            Image(systemName: "person.badge.minus")
                                .foregroundStyle(PickemsColors.warning)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(member.displayName)")
                        .disabled(isWorkingMembers)
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                }

                Menu {
                    ForEach(otherMembers) { member in
                        Button(member.displayName) {
                            memberToPromote = member
                        }
                    }
                } label: {
                    Label("Transfer Commissioner…", systemImage: "gavel")
                        .foregroundStyle(theme.accent)
                }
                .listRowBackground(PickemsColors.cardBackground)
                .disabled(isWorkingMembers)
            }

            Button(role: .destructive) {
                showDeleteLeagueConfirm = true
            } label: {
                Label("Delete League", systemImage: "trash")
            }
            .listRowBackground(PickemsColors.cardBackground)
            .disabled(isWorkingMembers)

            if let memberActionError {
                Text(memberActionError)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.warning)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        } header: {
            Text("Members & Ownership")
        } footer: {
            Text("Remove members, transfer commissioner (one at a time), or delete the entire league. Deleting erases all picks and standings.")
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, help: HelpTopic? = nil) -> some View {
        HStack {
            Text(title)
            if let help {
                Spacer()
                HelpInfoButton(topic: help, size: .caption)
            }
        }
    }

    private var pickemsLockFooter: String {
        if !liveGroup.rules.pickDeadline.isRolling {
            return "The whole slate locks at the earliest kickoff. Switch to rolling lock to lock each game at its own kickoff instead. If a week is in progress, you choose whether it applies now or next week."
        }
        if rules.pickDeadline == .rolling {
            return "Each game locks at its own kickoff. Later games stay open, and those picks stay hidden until that kickoff. Switching back to the entire slate applies when the next week opens."
        }
        return "The whole slate locks at the earliest kickoff. Applies when the next week opens."
    }

    /// Weeks to check for one in progress — the commissioner may be browsing another week.
    private var rollingCandidateWeeks: [WeekSummary] {
        let service = appState.groupService
        var weeks: [WeekSummary] = []
        if let current = service.currentWeek {
            weeks.append(current)
        }
        weeks.append(contentsOf: service.availableWeeks)
        return weeks
    }

    private func beginRollingSwitch() {
        rollingError = nil
        rollingStatus = nil
        let (phase, week) = RollingLockSwitch.leaguePhase(weeks: rollingCandidateWeeks)
        switch phase {
        case .inProgress:
            rollingPromptWeek = week
        case .allGamesStarted:
            performRollingSwitch(applyTo: nil, note: RollingLockSwitch.allGamesStartedNote)
        case .notInProgress:
            performRollingSwitch(applyTo: nil)
        }
    }

    /// `applyTo` nil only changes `rules.pickDeadline` (takes effect next week).
    private func performRollingSwitch(applyTo week: WeekSummary?, note: String? = nil) {
        rollingPromptWeek = nil
        isSwitchingToRolling = true
        Task {
            defer { isSwitchingToRolling = false }
            do {
                let weekChanged = try await appState.groupService.switchToRollingLock(
                    groupId: group.id,
                    weekId: week?.id,
                    applyToCurrentWeek: week != nil
                )
                // Keep the unsaved form in step so Save can't write first kickoff back.
                rules.pickDeadline = .rolling
                rules.allowLatePicks = false
                let successMessage: String = RollingLockSwitch.successMessage(
                    appliedToWeek: weekChanged,
                    weekNumber: week?.weekNumber,
                    askedToApply: week != nil
                )
                rollingStatus = note ?? successMessage
                PickemsHaptics.success()
            } catch {
                rollingError = UserFacingError.message(for: error, context: .write)
                    ?? "Couldn't switch to rolling lock. Try again."
                PickemsHaptics.warning()
            }
        }
    }

    private var lockModeBinding: Binding<DeadlinePolicy> {
        Binding(
            get: { rules.pickDeadline == .rolling ? .rolling : .firstKickoff },
            set: { mode in
                rules.pickDeadline = mode
                if mode == .rolling {
                    rules.allowLatePicks = false
                }
            }
        )
    }

    private func save() {
        isSaving = true
        if rules.pickDeadline == .custom {
            rules.pickDeadline = .firstKickoff
        }
        if rules.pickDeadline == .rolling {
            rules.allowLatePicks = false
        }
        Task {
            do {
                let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedName != liveGroup.name {
                    try await appState.groupService.renameGroup(groupId: group.id, name: trimmedName)
                }
                try await appState.groupService.updateRules(groupId: group.id, rules: rules)
                try await appState.groupService.setPublic(groupId: group.id, isPublic: isPublic)
                try await appState.groupService.setCommissionerOnlyInvites(
                    groupId: group.id,
                    enabled: commissionerOnlyInvites
                )
                PickemsHaptics.success()
                dismiss()
            } catch {
                UserFacingError.apply(error, to: &appState.groupService.errorMessage, context: .write)
                identityError = UserFacingError.message(for: error, context: .write)
                    ?? "Couldn't save those settings."
            }
            isSaving = false
        }
    }

    private func saveCustomCode() {
        identityError = nil
        isUpdatingCode = true
        Task {
            do {
                try await appState.groupService.updateInviteCode(groupId: group.id, newCode: customCode)
                PickemsHaptics.success()
                isEditingCode = false
                codeFieldFocused = false
            } catch {
                identityError = error.localizedDescription
                PickemsHaptics.warning()
            }
            isUpdatingCode = false
        }
    }

    private func regenerateCode() {
        identityError = nil
        isUpdatingCode = true
        Task {
            do {
                try await appState.groupService.regenerateInviteCode(groupId: group.id)
                PickemsHaptics.success()
            } catch {
                identityError = error.localizedDescription
                PickemsHaptics.warning()
            }
            isUpdatingCode = false
        }
    }

    private func removeMember(_ member: GroupMember) {
        memberActionError = nil
        isWorkingMembers = true
        Task {
            defer { isWorkingMembers = false }
            do {
                try await appState.groupService.removeMember(groupId: group.id, userId: member.id)
                PickemsHaptics.success()
            } catch {
                memberActionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func transferCommissioner(to member: GroupMember) {
        memberActionError = nil
        isWorkingMembers = true
        Task {
            defer { isWorkingMembers = false }
            do {
                try await appState.groupService.transferCommissioner(groupId: group.id, toUserId: member.id)
                PickemsHaptics.success()
                dismiss()
            } catch {
                memberActionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func deleteLeague() {
        memberActionError = nil
        isWorkingMembers = true
        Task {
            defer { isWorkingMembers = false }
            do {
                try await appState.groupService.deleteGroup(groupId: group.id)
                PickemsHaptics.success()
                dismiss()
            } catch {
                memberActionError = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }

    private func closeSeason() {
        closeSeasonError = nil
        Task {
            do {
                try await appState.groupService.closeSeason(groupId: group.id, seasonYear: seasonYearToClose)
                PickemsHaptics.success()
            } catch {
                closeSeasonError = error.localizedDescription
            }
        }
    }

}
