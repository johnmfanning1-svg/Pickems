import SwiftUI

struct CommissionerSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Pinned for this presentation. Snapshots update `group`; they do not
    /// change this id, so `@State` route survives a Firestore refresh.
    let groupId: String
    @State private var fallbackGroup: PickemGroup
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
    @State private var route: CommissionerSheet?
    /// Manage Pickems push. Ids only — a member snapshot must not pop it.
    @State private var picksRoute: CommissionerPicksRoute?
    @State private var capturedPicksMember: GroupMember?
    @State private var capturedPicksWeek: WeekSummary?
    /// League and week frozen when Reopen Selections was tapped.
    /// The alert is presented from this value (`presenting:`), not a second flag.
    @State private var reopenSelectionsTarget: DeadlineEditCapture?
    @State private var scoringSwitch: CommissionerScoringSwitch
    @State private var isSwitchingToRolling = false
    @State private var rollingPromptWeek: WeekSummary?
    @State private var rollingStatus: String?
    @State private var rollingError: String?

    @FocusState private var codeFieldFocused: Bool

    init(groupId: String, seed: PickemGroup) {
        self.groupId = groupId
        _fallbackGroup = State(initialValue: seed)
        _rules = State(initialValue: seed.rules)
        _isPublic = State(initialValue: seed.isPublic)
        _commissionerOnlyInvites = State(initialValue: seed.commissionerOnlyInvites == true)
        _groupName = State(initialValue: seed.name)
        _scoringSwitch = State(initialValue: CommissionerScoringSwitch())
    }

    /// Live league when it is still this presentation. Otherwise the last
    /// copy we had, so a nil flicker cannot blank the form.
    private var group: PickemGroup {
        if let live = appState.groupService.selectedGroup, live.id == groupId { return live }
        if let listed = appState.groupService.groups.first(where: { $0.id == groupId }) { return listed }
        return fallbackGroup
    }

    private var liveGroup: PickemGroup { group }

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
            settingsFormWithSeasonAlerts
                .navigationDestination(item: $picksRoute) { (route: CommissionerPicksRoute) in
                    managePicksDestination(route)
                }
                .task { await openPendingDeadlineEditor() }
                .task { await loadCommissionerWeekContext() }
                .onChange(of: groupId) { (previous: String, next: String) in
                    route = CommissionerSheetStability.routeAfterGroupRefresh(
                        route: route,
                        previousGroupId: previous,
                        groupId: next
                    )
                    picksRoute = CommissionerSheetStability.routeAfterGroupRefresh(
                        route: picksRoute,
                        previousGroupId: previous,
                        groupId: next
                    )
                }
        }
        // On the stack, not the alert chain. Several `.alert`s on the same
        // view as `.sheet` dismiss the sheet when a listener refreshes them.
        .sheet(item: $route) { (r: CommissionerSheet) in
            routeContent(r)
        }
    }

    // MARK: - Form

    private var settingsForm: some View {
        Form {
            CommissionerWeekAdminSections(
                present: { (request: CommissionerSheetRequest) in presentCommissionerSheet(request) },
                requestReopenSelections: { (week: WeekSummary) in presentReopenSelectionsConfirm(week) },
                managePicks: { (member: GroupMember, week: WeekSummary) in
                    capturedPicksMember = member
                    capturedPicksWeek = week
                    picksRoute = CommissionerPicksRoute(memberId: member.id, weekId: week.id)
                }
            )
            leagueIdentitySection
            membersRowSection
            CommissionerScoringSection(groupId: group.id, rules: $rules, model: scoringSwitch)
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

    private var slateConfigurationFooter: String {
        if rules.selectionMode == .member {
            let base = "Each member selects this many games. Weekly game target = members × Selections. You’ll set a Selection deadline each week."
            return "\(base) \(SelectionVetoPolicy.settingsFooter(memberCount: liveGroup.memberCount))"
        }
        return "You choose every game for the group each week."
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

                Toggle("Veto", isOn: $rules.vetoEnabled)
                    .disabled(!SelectionVetoPolicy.canConfigure(memberCount: liveGroup.memberCount))
                    .listRowBackground(PickemsColors.cardBackground)

                if rules.vetoEnabled, SelectionVetoPolicy.canConfigure(memberCount: liveGroup.memberCount) {
                    Stepper(
                        "Votes needed: \(vetoVotesBinding.wrappedValue)",
                        value: vetoVotesBinding,
                        in: 1...max(SelectionVetoPolicy.maxVotesNeeded(memberCount: liveGroup.memberCount), 1)
                    )
                    .listRowBackground(PickemsColors.cardBackground)
                }
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

    private var closeSeasonAlertTitle: String {
        "Close Season \(seasonYearToClose.pickemsYearString)?"
    }

    /// League-type prompt, Reopen Selections, rolling-lock prompt, Close Season confirm.
    /// All sit on the settings root, outside the Form.
    private var settingsFormWithSeasonAlerts: some View {
        settingsFormWithPromptAlerts
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

    private var reopenSelectionsPresented: Binding<Bool> {
        Binding(
            get: { reopenSelectionsTarget != nil },
            set: { (isPresented: Bool) in if !isPresented { reopenSelectionsTarget = nil } }
        )
    }

    private var settingsFormWithPromptAlerts: some View {
        settingsForm
            .modifier(scoringPromptAlert)
            .alert(
                "Reopen Selections?",
                isPresented: reopenSelectionsPresented,
                presenting: reopenSelectionsTarget
            ) { (target: DeadlineEditCapture) in
                Button("Reopen Selections") {
                    let write = target.writeTarget(
                        selectedGroupId: appState.groupService.selectedGroup?.id,
                        selectedWeekId: appState.groupService.currentWeek?.id
                    )
                    appState.picksViewModel.reopenSelections(
                        groupId: write.groupId,
                        weekId: write.weekId,
                        appState: appState
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: { (_: DeadlineEditCapture) in
                Text("Members can add and remove Selections again. Pickems close until you open the week.")
            }
    }

    private var scoringPromptAlert: CommissionerScoringPromptAlert {
        CommissionerScoringPromptAlert(
            model: scoringSwitch,
            groupId: group.id,
            rules: $rules,
            appState: appState
        )
    }

    // MARK: - Sheets

    @ViewBuilder
    private func managePicksDestination(_ route: CommissionerPicksRoute) -> some View {
        if let member = picksMember(route.memberId), let week = picksWeek(route.weekId) {
            CommissionerManagePicksSheet(
                member: member,
                week: week,
                groupId: groupId,
                slateGames: appState.pickService.slateGames
            )
            .pickemsEnvironment(appState)
        } else {
            ContentUnavailableView(
                "Pickems Unavailable",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("That member or week is no longer in this league.")
            )
        }
    }

    private func picksMember(_ memberId: String) -> GroupMember? {
        if let live = appState.groupService.members.first(where: { $0.id == memberId }) { return live }
        if capturedPicksMember?.id == memberId { return capturedPicksMember }
        return nil
    }

    private func picksWeek(_ weekId: String) -> WeekSummary? {
        if capturedPicksWeek?.id == weekId { return capturedPicksWeek }
        if appState.groupService.currentWeek?.id == weekId { return appState.groupService.currentWeek }
        guard appState.groupService.availableWeeksBelong(to: groupId) else { return nil }
        return appState.groupService.availableWeeks.first { $0.id == weekId }
    }

    @ViewBuilder
    private func routeContent(_ r: CommissionerSheet) -> some View {
        // The sheet item is the only week. A sibling `@State` edit is nil on the
        // first frame of `sheet(item:)` and used to show "No Active Week".
        switch r {
        case .selectionDeadline(let edit):
            selectionDeadlineSheet(
                CommissionerDeadlinePresentation.presentedSelectionEdit(on: r, siblingEdit: nil) ?? edit
            )
        case .pickDeadline(let edit):
            pickDeadlineSheet(
                CommissionerDeadlinePresentation.presentedPickEdit(on: r, siblingEdit: nil) ?? edit
            )
        case .adminGameBrowse:
            adminGameBrowseSheet
        case .members:
            membersSheet
        case .selections(let week):
            selectionsAdminSheet(week)
        case .slate(let week):
            slateAdminSheet(week)
        case .rankTies(let draft, let capture):
            rankTiesSheet(draft, capture: capture)
        }
    }

    private func selectionsAdminSheet(_ week: WeekSummary) -> some View {
        CommissionerSelectionsAdminSheet(week: week, groupId: group.id)
            .pickemsEnvironment(appState)
    }

    private func slateAdminSheet(_ week: WeekSummary) -> some View {
        CommissionerSlateSheet(week: week)
            .pickemsEnvironment(appState)
    }

    private func rankTiesSheet(_ draft: TieRankDraft, capture: DeadlineEditCapture) -> some View {
        CommissionerRankTiesSheet(
            weekLabel: capture.weekLabel,
            entries: draft.entries
        ) { (orderedIds: [String]) in
            try await appState.groupService.resolveTieGroup(
                groupId: capture.groupId,
                weekId: capture.weekId,
                orderedUserIds: orderedIds
            )
        }
        .pickemsEnvironment(appState)
    }

    private func loadCommissionerWeekContext() async {
        await appState.groupService.loadAvailableWeeks(groupId: groupId)
        await appState.picksViewModel.ensureTeamRanks(appState: appState)
    }

    /// Countdown prompt tap or Selection-deadline push: open the matching editor
    /// for this league (and the tapped week) once settings are on screen.
    /// The write target is frozen here, before the present delay, so a league
    /// switch during that delay cannot retarget the save.
    private func openPendingDeadlineEditor() async {
        guard let target = appState.pendingDeadlineEditor else { return }
        appState.pendingDeadlineEditor = nil
        guard target.matches(groupId: groupId) else { return }
        let service = appState.groupService
        if let weekId = target.weekId,
           service.selectedGroup?.id == groupId,
           service.currentWeek?.id != weekId,
           service.availableWeeksBelong(to: groupId),
           let week = service.availableWeeks.first(where: { $0.id == weekId }) {
            appState.selectObservedWeek(week)
        }
        let weekId = target.weekId ?? service.currentWeek?.id
        guard let weekId else { return }
        // Let the settings sheet finish presenting before stacking the editor.
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        let week = displayedWeek(groupId: groupId, weekId: weekId)
        switch target.kind {
        case .selections:
            route = CommissionerDeadlinePresentation.pendingSelection(
                settingsGroupId: groupId,
                weekId: weekId,
                displayedWeek: week
            )
        case .pickems:
            guard let week else { return }
            route = .pickDeadline(
                CommissionerDeadlinePresentation.pickEdit(settingsGroupId: groupId, week: week)
            )
        }
    }

    private func presentCommissionerSheet(_ request: CommissionerSheetRequest) {
        guard let sheet = CommissionerDeadlinePresentation.route(
            for: request,
            settingsGroupId: groupId,
            selectedGroupId: appState.groupService.selectedGroup?.id
        ) else { return }
        route = sheet
    }

    private func presentReopenSelectionsConfirm(_ week: WeekSummary) {
        guard appState.groupService.selectedGroup?.id == group.id,
              WeekTransition.canReopenSelections(week) else { return }
        reopenSelectionsTarget = DeadlineEditCapture(
            groupId: group.id,
            weekId: week.id,
            weekLabel: week.displayLabel,
            isRollingLock: week.isRollingLock
        )
    }

    /// Week fields for display only. Nil when the on-screen league is no longer `groupId`,
    /// so a switch cannot supply another league's deadline as the editor seed.
    private func displayedWeek(groupId: String, weekId: String) -> WeekSummary? {
        let service = appState.groupService
        guard service.selectedGroup?.id == groupId else { return nil }
        if service.currentWeek?.id == weekId {
            return service.currentWeek
        }
        guard service.availableWeeksBelong(to: groupId) else { return nil }
        return service.availableWeeks.first { $0.id == weekId }
    }

    private func selectionDeadlineSheet(_ edit: SelectionDeadlineEdit) -> some View {
        SelectionDeadlineSheet(
            groupId: edit.capture.groupId,
            weekId: edit.capture.weekId,
            weekLabel: edit.capture.weekLabel,
            initialDeadline: edit.initialDeadline
        ) { groupId, weekId, deadline in
            let write = DeadlineEditCapture(
                groupId: groupId,
                weekId: weekId,
                weekLabel: edit.capture.weekLabel,
                isRollingLock: edit.capture.isRollingLock
            ).writeTarget(
                selectedGroupId: appState.groupService.selectedGroup?.id,
                selectedWeekId: appState.groupService.currentWeek?.id
            )
            appState.picksViewModel.setSelectionDeadline(
                deadline,
                groupId: write.groupId,
                weekId: write.weekId,
                appState: appState
            )
        }
        .pickemsEnvironment(appState)
    }

    private func pickDeadlineSheet(_ edit: PickDeadlineEdit) -> some View {
        PickDeadlineEditorSheet(
            groupId: edit.capture.groupId,
            weekId: edit.capture.weekId,
            weekLabel: edit.capture.weekLabel,
            weekStatus: edit.weekStatus,
            initialDeadline: edit.initialDeadline,
            isPastDeadline: edit.isPastDeadline,
            isRollingLock: edit.capture.isRollingLock,
            onLockRemainingNow: { groupId, weekId in
                let write = DeadlineEditCapture(
                    groupId: groupId,
                    weekId: weekId,
                    weekLabel: edit.capture.weekLabel,
                    isRollingLock: true
                ).writeTarget(
                    selectedGroupId: appState.groupService.selectedGroup?.id,
                    selectedWeekId: appState.groupService.currentWeek?.id
                )
                appState.picksViewModel.lockRemainingGamesNow(
                    groupId: write.groupId,
                    weekId: write.weekId,
                    appState: appState
                )
            }
        ) { groupId, weekId, isRollingLock, deadline, reopen, unlock in
            let write = DeadlineEditCapture(
                groupId: groupId,
                weekId: weekId,
                weekLabel: edit.capture.weekLabel,
                isRollingLock: isRollingLock
            ).writeTarget(
                selectedGroupId: appState.groupService.selectedGroup?.id,
                selectedWeekId: appState.groupService.currentWeek?.id
            )
            appState.picksViewModel.setPickDeadline(
                deadline,
                groupId: write.groupId,
                weekId: write.weekId,
                isRollingLock: isRollingLock,
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

    private var membersSheet: some View {
        CommissionerMembersSheet(
            groupId: group.id,
            commissionerId: liveGroup.commissionerId
        ) {
            // Transfer or delete: these settings no longer apply.
            route = nil
            dismiss()
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

    /// Members list, transfer and delete live in `CommissionerMembersSheet`.
    private var membersRowSection: some View {
        Section {
            CommissionerAdminRow(
                title: "Members",
                systemImage: "person.3",
                summary: CommissionerAdminSummary.members(count: appState.groupService.members.count),
                hint: "Remove members, transfer commissioner, or delete the league."
            ) {
                route = .members
            }
        } header: {
            Text("Members & Ownership")
        } footer: {
            Text("Remove members, transfer commissioner (one at a time), or delete the entire league.")
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

    private var vetoVotesBinding: Binding<Int> {
        Binding(
            get: {
                SelectionVetoPolicy.clampedVotesNeeded(
                    rules.vetoVotesNeeded,
                    memberCount: liveGroup.memberCount
                )
            },
            set: { rules.vetoVotesNeeded = $0 }
        )
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
        rules.vetoVotesNeeded = SelectionVetoPolicy.clampedVotesNeeded(
            rules.vetoVotesNeeded,
            memberCount: liveGroup.memberCount
        )
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

/// Manage Pickems push. The id is week + member, not the member value, so a
/// roster refresh cannot pop the editor.
struct CommissionerPicksRoute: Identifiable, Hashable {
    var memberId: String
    var weekId: String
    var id: String { "\(weekId)|\(memberId)" }
}
