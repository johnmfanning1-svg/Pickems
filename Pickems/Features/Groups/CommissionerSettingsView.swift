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
    @State private var route: CommissionerSheet?
    @State private var showReopenSelectionsConfirm = false
    /// League and week frozen when Reopen Selections was tapped.
    @State private var reopenSelectionsTarget: DeadlineEditCapture?
    /// League and week frozen when the Selection deadline editor opened.
    @State private var selectionDeadlineEdit: SelectionDeadlineEdit?
    /// League and week frozen when the Pickems deadline editor opened.
    @State private var pickDeadlineEdit: PickDeadlineEdit?
    @State private var scoringSwitch: CommissionerScoringSwitch
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
        _scoringSwitch = State(initialValue: CommissionerScoringSwitch())
    }

    private var liveGroup: PickemGroup {
        appState.groupService.selectedGroup?.id == group.id
            ? (appState.groupService.selectedGroup ?? group)
            : group
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
                present: { (r: CommissionerSheet) in presentCommissionerSheet(r) },
                requestReopenSelections: { presentReopenSelectionsConfirm() }
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

    private var settingsFormWithPromptAlerts: some View {
        settingsForm
            .modifier(scoringPromptAlert)
            .alert("Reopen Selections?", isPresented: $showReopenSelectionsConfirm) {
                Button("Reopen Selections") {
                    guard let target = reopenSelectionsTarget else { return }
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
            } message: {
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

    private var settingsFormWithSheets: some View {
        settingsFormWithSeasonAlerts
            .sheet(item: $route) { (r: CommissionerSheet) in
                routeContent(r)
            }
            .task { await openPendingDeadlineEditor() }
            .task { await loadCommissionerWeekContext() }
    }

    @ViewBuilder
    private func routeContent(_ r: CommissionerSheet) -> some View {
        switch r {
        case .selectionDeadline:
            if let selectionDeadlineEdit {
                selectionDeadlineSheet(selectionDeadlineEdit)
            } else {
                missingDeadlineTarget
            }
        case .pickDeadline:
            if let pickDeadlineEdit {
                pickDeadlineSheet(pickDeadlineEdit)
            } else {
                missingDeadlineTarget
            }
        case .adminGameBrowse:
            adminGameBrowseSheet
        case .members:
            membersSheet
        case .selections:
            selectionsAdminSheet
        case .slate:
            slateAdminSheet
        case .rankTies(let draft):
            rankTiesSheet(draft)
        }
    }

    private var selectionsAdminSheet: some View {
        CommissionerSelectionsAdminSheet()
            .pickemsEnvironment(appState)
    }

    private var slateAdminSheet: some View {
        CommissionerSlateSheet()
            .pickemsEnvironment(appState)
    }

    private func rankTiesSheet(_ draft: TieRankDraft) -> some View {
        CommissionerRankTiesSheet(
            weekLabel: appState.groupService.currentWeek?.displayLabel ?? "This week",
            entries: draft.entries
        ) { (orderedIds: [String]) in
            guard let groupId = appState.groupService.selectedGroup?.id,
                  let weekId = appState.groupService.currentWeek?.id else {
                throw GroupService.GroupError.groupNotFound
            }
            try await appState.groupService.resolveTieGroup(
                groupId: groupId,
                weekId: weekId,
                orderedUserIds: orderedIds
            )
        }
        .pickemsEnvironment(appState)
    }

    private func loadCommissionerWeekContext() async {
        if let groupId = appState.groupService.selectedGroup?.id {
            await appState.groupService.loadAvailableWeeks(groupId: groupId)
        }
        await appState.picksViewModel.ensureTeamRanks(appState: appState)
    }

    /// Countdown prompt tap or Selection-deadline push: open the matching editor
    /// for this league (and the tapped week) once settings are on screen.
    /// The write target is frozen here, before the present delay, so a league
    /// switch during that delay cannot retarget the save.
    private func openPendingDeadlineEditor() async {
        guard let target = appState.pendingDeadlineEditor else { return }
        appState.pendingDeadlineEditor = nil
        guard target.matches(groupId: group.id) else { return }
        let groupId = group.id
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
            selectionDeadlineEdit = SelectionDeadlineEdit(
                capture: deadlineCapture(groupId: groupId, weekId: weekId, week: week),
                initialDeadline: week?.selectionDeadline
            )
            route = .selectionDeadline
        case .pickems:
            guard let week else { return }
            pickDeadlineEdit = makePickDeadlineEdit(groupId: groupId, week: week)
            route = .pickDeadline
        }
    }

    private func presentCommissionerSheet(_ sheet: CommissionerSheet) {
        switch sheet {
        case .selectionDeadline:
            guard let edit = makeSelectionDeadlineEdit() else { return }
            selectionDeadlineEdit = edit
        case .pickDeadline:
            guard let edit = makePickDeadlineEdit() else { return }
            pickDeadlineEdit = edit
        default:
            break
        }
        route = sheet
    }

    private func presentReopenSelectionsConfirm() {
        guard appState.groupService.selectedGroup?.id == group.id,
              let week = appState.groupService.currentWeek,
              WeekTransition.canReopenSelections(week) else { return }
        reopenSelectionsTarget = DeadlineEditCapture(
            groupId: group.id,
            weekId: week.id,
            weekLabel: week.displayLabel,
            isRollingLock: week.isRollingLock
        )
        showReopenSelectionsConfirm = true
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

    private func makeSelectionDeadlineEdit() -> SelectionDeadlineEdit? {
        guard appState.groupService.selectedGroup?.id == group.id,
              let week = appState.groupService.currentWeek else { return nil }
        return SelectionDeadlineEdit(
            capture: deadlineCapture(groupId: group.id, weekId: week.id, week: week),
            initialDeadline: week.selectionDeadline
        )
    }

    private func makePickDeadlineEdit() -> PickDeadlineEdit? {
        guard appState.groupService.selectedGroup?.id == group.id,
              let week = appState.groupService.currentWeek else { return nil }
        return makePickDeadlineEdit(groupId: group.id, week: week)
    }

    private func makePickDeadlineEdit(groupId: String, week: WeekSummary) -> PickDeadlineEdit {
        let initialDeadline: Date? = week.isRollingLock
            ? (week.remainingLockAt ?? week.effectiveWeekLockAt ?? week.pickDeadline)
            : week.pickDeadline
        return PickDeadlineEdit(
            capture: deadlineCapture(groupId: groupId, weekId: week.id, week: week),
            weekStatus: week.status,
            initialDeadline: initialDeadline,
            isPastDeadline: WeekTransition.arePicksFullyLocked(week)
        )
    }

    private func deadlineCapture(groupId: String, weekId: String, week: WeekSummary?) -> DeadlineEditCapture {
        DeadlineEditCapture(
            groupId: groupId,
            weekId: weekId,
            weekLabel: week?.displayLabel ?? "This week",
            isRollingLock: week?.isRollingLock ?? false
        )
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

    private var missingDeadlineTarget: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Active Week",
                systemImage: "calendar",
                description: Text("Open Commissioner Settings again after a week is selected.")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { route = nil }
                }
            }
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
