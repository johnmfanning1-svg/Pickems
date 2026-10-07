import SwiftUI

/// Commissioner Settings → Scoring. The one place league type (Against the Spread /
/// Straight Up) is changed. Writes go through `setLeaguePickMode` immediately (not
/// on Save), like Switch to Rolling Lock, so the current week is handled correctly.
struct CommissionerScoringSection: View {
    @Environment(AppState.self) private var appState

    let groupId: String
    /// The form's unsaved rules. Kept in step so Save can't write the old type back.
    @Binding var rules: GroupRules

    @State private var isSwitching = false
    @State private var prompt: PickModePrompt?
    @State private var status: String?
    @State private var error: String?

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
        .alert(promptTitle, isPresented: promptPresented, presenting: prompt) { (prompt: PickModePrompt) in
            promptActions(prompt)
        } message: { (prompt: PickModePrompt) in
            Text(promptMessage(prompt))
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
            set: { (newMode: PickMode) in beginSwitch(to: newMode) }
        )
    }

    private var leagueTypePicker: some View {
        Picker("League type", selection: leagueTypeBinding) {
            ForEach(PickMode.allCases) { (mode: PickMode) in
                Text(mode.displayName).tag(mode)
            }
        }
        .disabled(isSwitching)
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
        if isSwitching {
            HStack { ProgressView(); Text("Changing league type…") }
                .listRowBackground(PickemsColors.cardBackground)
        }
        if let status {
            Text(status)
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
                .listRowBackground(PickemsColors.cardBackground)
        }
        if let error {
            Text(error)
                .font(.caption)
                .foregroundStyle(PickemsColors.warning)
                .listRowBackground(PickemsColors.cardBackground)
        }
    }

    // MARK: - Prompt

    private var promptPresented: Binding<Bool> {
        Binding<Bool>(
            get: { prompt != nil },
            set: { (isPresented: Bool) in if !isPresented { prompt = nil } }
        )
    }

    private var promptTitle: String {
        guard let prompt else { return "" }
        switch prompt.kind {
        case .ask:
            return LeaguePickModeSwitch.askTitle(newMode: prompt.newMode)
        case .nextWeekOnly:
            return LeaguePickModeSwitch.nextWeekOnlyTitle(newMode: prompt.newMode)
        }
    }

    private func promptMessage(_ prompt: PickModePrompt) -> String {
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

    @ViewBuilder
    private func promptActions(_ prompt: PickModePrompt) -> some View {
        if prompt.kind == .ask {
            Button(LeaguePickModeSwitch.applyNowTitle) {
                performSwitch(prompt.newMode, weekId: prompt.weekId, applyToCurrentWeek: true, currentWeekMode: prompt.currentWeekMode)
            }
        }
        Button(LeaguePickModeSwitch.nextWeekTitle) {
            performSwitch(prompt.newMode, weekId: prompt.weekId, applyToCurrentWeek: false, currentWeekMode: prompt.currentWeekMode)
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Actions

    private func beginSwitch(to newMode: PickMode) {
        guard newMode != leagueMode, !isSwitching else { return }
        status = nil
        error = nil
        let week: WeekSummary? = leagueWeek
        let currentWeekMode: PickMode = week?.resolvedPickMode(leagueMode: leagueMode) ?? leagueMode
        let phase = LeaguePickModeSwitch.phase(week: week, selectionsMade: selectionsMade)
        switch LeaguePickModeSwitch.decision(for: phase) {
        case .applyNow(let weekId):
            performSwitch(newMode, weekId: weekId, applyToCurrentWeek: true, currentWeekMode: currentWeekMode)
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

    private func performSwitch(_ newMode: PickMode, weekId: String?, applyToCurrentWeek: Bool, currentWeekMode: PickMode) {
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
                rules.pickMode = newMode
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
