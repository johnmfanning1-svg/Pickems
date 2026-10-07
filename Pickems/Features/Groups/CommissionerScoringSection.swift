import SwiftUI

/// Switching state for Commissioner Settings → Scoring. The alert lives on the
/// settings root (`CommissionerScoringPromptAlert`), not on the Form section.
@MainActor
@Observable
final class CommissionerScoringSwitch {
    /// Pending change that needs the commissioner to confirm.
    struct PickModePrompt: Identifiable, Equatable {
        enum Kind: Equatable {
            case ask
            case nextWeekOnly(weekScored: Bool)
        }

        let newMode: PickMode
        let currentWeekMode: PickMode
        let weekId: String
        let kind: Kind

        var id: String { "\(newMode.rawValue).\(weekId)" }
    }

    var isSwitching = false
    var prompt: PickModePrompt?
    var status: String?
    var error: String?

    var promptPresented: Binding<Bool> {
        Binding<Bool>(
            get: { self.prompt != nil },
            set: { (isPresented: Bool) in
                if !isPresented { self.prompt = nil }
            }
        )
    }

    var promptTitle: String {
        guard let prompt else { return "" }
        switch prompt.kind {
        case .ask:
            return LeaguePickModeSwitch.askTitle(newMode: prompt.newMode)
        case .nextWeekOnly:
            return LeaguePickModeSwitch.nextWeekOnlyTitle(newMode: prompt.newMode)
        }
    }

    func promptMessage(_ prompt: PickModePrompt) -> String {
        switch prompt.kind {
        case .ask:
            return LeaguePickModeSwitch.askMessage(newMode: prompt.newMode, currentMode: prompt.currentWeekMode)
        case .nextWeekOnly(let weekScored):
            return LeaguePickModeSwitch.nextWeekOnlyMessage(
                newMode: prompt.newMode,
                currentMode: prompt.currentWeekMode,
                weekScored: weekScored
            )
        }
    }

    func beginSwitch(
        to newMode: PickMode,
        leagueMode: PickMode,
        week: WeekSummary?,
        selectionsMade: Int,
        groupId: String,
        rules: Binding<GroupRules>,
        appState: AppState
    ) {
        guard newMode != leagueMode, !isSwitching else { return }
        status = nil
        error = nil
        let currentWeekMode: PickMode = week?.resolvedPickMode(leagueMode: leagueMode) ?? leagueMode
        let phase = LeaguePickModeSwitch.phase(week: week, selectionsMade: selectionsMade)
        switch LeaguePickModeSwitch.decision(for: phase) {
        case .applyNow(let weekId):
            performSwitch(
                newMode,
                weekId: weekId,
                applyToCurrentWeek: true,
                currentWeekMode: currentWeekMode,
                groupId: groupId,
                rules: rules,
                appState: appState
            )
        case .ask(let weekId):
            prompt = PickModePrompt(newMode: newMode, currentWeekMode: currentWeekMode, weekId: weekId, kind: .ask)
        case .nextWeekOnly(let weekId):
            let scored: Bool = week?.status == .scored
            prompt = PickModePrompt(
                newMode: newMode,
                currentWeekMode: currentWeekMode,
                weekId: weekId,
                kind: .nextWeekOnly(weekScored: scored)
            )
        }
    }

    func performSwitch(
        _ newMode: PickMode,
        weekId: String?,
        applyToCurrentWeek: Bool,
        currentWeekMode: PickMode,
        groupId: String,
        rules: Binding<GroupRules>,
        appState: AppState
    ) {
        prompt = nil
        isSwitching = true
        Task {
            defer { isSwitching = false }
            do {
                let applied: Bool = try await appState.groupService.setLeaguePickMode(
                    groupId: groupId,
                    pickMode: newMode,
                    weekId: weekId,
                    applyToCurrentWeek: applyToCurrentWeek
                )
                rules.wrappedValue.pickMode = newMode
                status = LeaguePickModeSwitch.successMessage(
                    newMode: newMode,
                    appliedToCurrentWeek: applied,
                    hadCurrentWeek: weekId != nil,
                    currentMode: currentWeekMode
                )
                PickemsHaptics.success()
            } catch {
                self.error = UserFacingError.message(for: error, context: .write)
                    ?? "Couldn't change the league type. Try again."
                PickemsHaptics.warning()
            }
        }
    }
}

/// Attaches the league-type confirm to the settings screen root, outside the Form.
struct CommissionerScoringPromptAlert: ViewModifier {
    var model: CommissionerScoringSwitch
    let groupId: String
    @Binding var rules: GroupRules
    var appState: AppState

    func body(content: Content) -> some View {
        @Bindable var model = model
        content.alert(
            model.promptTitle,
            isPresented: model.promptPresented,
            presenting: model.prompt
        ) { (prompt: CommissionerScoringSwitch.PickModePrompt) in
            promptActions(prompt)
        } message: { (prompt: CommissionerScoringSwitch.PickModePrompt) in
            Text(model.promptMessage(prompt))
        }
    }

    @ViewBuilder
    private func promptActions(_ prompt: CommissionerScoringSwitch.PickModePrompt) -> some View {
        if prompt.kind == .ask {
            Button(LeaguePickModeSwitch.applyNowTitle) {
                model.performSwitch(
                    prompt.newMode,
                    weekId: prompt.weekId,
                    applyToCurrentWeek: true,
                    currentWeekMode: prompt.currentWeekMode,
                    groupId: groupId,
                    rules: $rules,
                    appState: appState
                )
            }
        }
        Button(LeaguePickModeSwitch.nextWeekTitle) {
            model.performSwitch(
                prompt.newMode,
                weekId: prompt.weekId,
                applyToCurrentWeek: false,
                currentWeekMode: prompt.currentWeekMode,
                groupId: groupId,
                rules: $rules,
                appState: appState
            )
        }
        Button("Cancel", role: .cancel) {}
    }
}

/// Commissioner Settings → Scoring. The one place league type (Against the Spread /
/// Straight Up) is changed. Writes go through `setLeaguePickMode` immediately (not
/// on Save), like Switch to Rolling Lock, so the current week is handled correctly.
struct CommissionerScoringSection: View {
    @Environment(AppState.self) private var appState

    let groupId: String
    /// The form's unsaved rules. Kept in step so Save can't write the old type back.
    @Binding var rules: GroupRules
    var model: CommissionerScoringSwitch

    var body: some View {
        Section {
            leagueTypePicker
            currentWeekRow
            feedbackRows
        } header: {
            Text("Scoring")
        } footer: {
            Text(LeaguePickModeSwitch.footer)
        }
    }

    // MARK: - Data

    private var leagueMode: PickMode {
        let service = appState.groupService
        if service.selectedGroup?.id == groupId, let group = service.selectedGroup {
            return group.rules.pickMode
        }
        return service.groups.first { $0.id == groupId }?.rules.pickMode ?? rules.pickMode
    }

    /// The league's current week: the calendar week when loaded, else the observed week.
    private var leagueWeek: WeekSummary? {
        let service = appState.groupService
        guard let activeId = service.cfbWeek.map({ CFBWeekSync.weekId(for: $0) }) else {
            return service.currentWeek
        }
        if service.currentWeek?.id == activeId { return service.currentWeek }
        return service.availableWeeks.first { $0.id == activeId } ?? service.currentWeek
    }

    /// Selections made on the league week (nominations or commissioner-added games).
    private var selectionsMade: Int {
        guard let week = leagueWeek, week.id == appState.groupService.currentWeek?.id else { return 0 }
        let nominations: Int = appState.pickService.nominations.count
        let slate: Int = appState.pickService.slateGames.count
        return nominations + slate
    }

    // MARK: - Rows

    private var leagueTypeBinding: Binding<PickMode> {
        Binding<PickMode>(
            get: { leagueMode },
            set: { (newMode: PickMode) in
                model.beginSwitch(
                    to: newMode,
                    leagueMode: leagueMode,
                    week: leagueWeek,
                    selectionsMade: selectionsMade,
                    groupId: groupId,
                    rules: $rules,
                    appState: appState
                )
            }
        )
    }

    private var leagueTypePicker: some View {
        Picker("League type", selection: leagueTypeBinding) {
            ForEach(PickMode.allCases) { (mode: PickMode) in
                Text(mode.displayName).tag(mode)
            }
        }
        .disabled(model.isSwitching)
        .listRowBackground(PickemsColors.cardBackground)
    }

    /// Shown only while this week is scored differently from the league (e.g. after Start next week).
    @ViewBuilder
    private var currentWeekRow: some View {
        if let week = leagueWeek {
            let weekMode: PickMode = week.resolvedPickMode(leagueMode: leagueMode)
            if weekMode != leagueMode {
                LabeledContent("This week", value: weekMode.displayName)
                    .listRowBackground(PickemsColors.cardBackground)
            }
        }
    }

    @ViewBuilder
    private var feedbackRows: some View {
        if model.isSwitching {
            switchingRow
        }
        if let status = model.status {
            Text(status)
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
                .listRowBackground(PickemsColors.cardBackground)
        }
        if let error = model.error {
            Text(error)
                .font(.caption)
                .foregroundStyle(PickemsColors.warning)
                .listRowBackground(PickemsColors.cardBackground)
        }
    }

    private var switchingRow: some View {
        HStack {
            ProgressView()
            Text("Changing league type…")
        }
        .listRowBackground(PickemsColors.cardBackground)
    }
}
