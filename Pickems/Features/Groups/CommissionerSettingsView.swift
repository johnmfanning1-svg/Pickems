import SwiftUI

struct CommissionerSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    let group: PickemGroup
    @State private var rules: GroupRules
    @State private var isPublic: Bool
    @State private var isSaving = false
    @State private var showCloseSeasonConfirm = false
    @State private var closeSeasonError: String?

    init(group: PickemGroup) {
        self.group = group
        _rules = State(initialValue: group.rules)
        _isPublic = State(initialValue: group.isPublic)
    }

    private var seasonYearToClose: Int {
        appState.groupService.cfbWeek?.seasonYear
            ?? appState.groupService.currentWeek?.seasonYear
            ?? Calendar.current.component(.year, from: Date())
    }

    private var seasonAlreadyClosed: Bool {
        appState.groupService.seasonArchives.contains { $0.seasonYear == seasonYearToClose }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Who selects games", selection: $rules.selectionMode) {
                        ForEach(SelectionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                } header: {
                    sectionHeader("Selection Mode", help: PickemsHelp.commissionerSettings)
                } footer: {
                    Text(rules.selectionMode == .member
                        ? "Members nominate games until the slate is full."
                        : "You choose every game for the group each week.")
                }

                Section {
                    Stepper("Games per week: \(rules.slateSize)", value: $rules.slateSize, in: 1...20)
                        .listRowBackground(PickemsColors.cardBackground)
                    if rules.selectionMode == .member {
                        Stepper("Selections per member: \(rules.selectionsPerMember)", value: $rules.selectionsPerMember, in: 1...10)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                } header: {
                    Text("Slate Configuration")
                }

                Section {
                    Picker("Pick deadline", selection: $rules.pickDeadline) {
                        ForEach(DeadlinePolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .listRowBackground(PickemsColors.cardBackground)

                    if rules.pickDeadline == .custom {
                        DatePicker(
                            "Custom deadline time",
                            selection: Binding(
                                get: { customDeadlineDate },
                                set: { updateCustomDeadline(from: $0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .listRowBackground(PickemsColors.cardBackground)
                    }

                    Picker("Tie breaker", selection: $rules.tieBreaker) {
                        ForEach(TieBreakerPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .listRowBackground(PickemsColors.cardBackground)

                    Toggle("Confidence pick (2x one game)", isOn: $rules.allowConfidencePick)
                        .listRowBackground(PickemsColors.cardBackground)
                    Toggle("Allow late picks", isOn: $rules.allowLatePicks)
                        .listRowBackground(PickemsColors.cardBackground)
                    if rules.allowLatePicks {
                        Stepper(
                            "Late penalty: \(rules.latePickPenaltyWins) win(s)",
                            value: $rules.latePickPenaltyWins,
                            in: 1...3
                        )
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                } header: {
                    sectionHeader("Deadlines & Ties", help: PickemsHelp.pickDeadline)
                } footer: {
                    Text("Changes apply to future weeks. Existing locked weeks are not affected.")
                }

                Section {
                    Toggle("List in Discover", isOn: $isPublic)
                        .listRowBackground(PickemsColors.cardBackground)
                    NavigationLink {
                        SubmissionStatusView()
                    } label: {
                        Label("Submission chase", systemImage: "person.crop.circle.badge.clock")
                    }
                    .listRowBackground(PickemsColors.cardBackground)
                } header: {
                    Text("Visibility & Chase")
                } footer: {
                    Text("Public leagues appear in Discover. Submission chase shows who still needs to lock picks.")
                }

                Section {
                    if seasonAlreadyClosed {
                        LabeledContent("Season \(seasonYearToClose)", value: "Archived")
                            .listRowBackground(PickemsColors.cardBackground)
                    } else {
                        Button(role: .destructive) {
                            showCloseSeasonConfirm = true
                        } label: {
                            if appState.groupService.isClosingSeason {
                                HStack {
                                    ProgressView()
                                    Text("Closing Season \(seasonYearToClose)…")
                                }
                            } else {
                                Label("Close Season \(seasonYearToClose)", systemImage: "trophy.fill")
                            }
                        }
                        .disabled(appState.groupService.isClosingSeason)
                        .listRowBackground(PickemsColors.cardBackground)
                    }

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
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle("Commissioner Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
            .confirmationDialog(
                "Close Season \(seasonYearToClose)?",
                isPresented: $showCloseSeasonConfirm,
                titleVisibility: .visible
            ) {
                Button("Close Season", role: .destructive) { closeSeason() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This archives \(seasonYearToClose) standings and resets everyone’s season record. This cannot be undone.")
            }
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

    private func save() {
        isSaving = true
        Task {
            do {
                try await appState.groupService.updateRules(groupId: group.id, rules: rules)
                try await appState.groupService.setPublic(groupId: group.id, isPublic: isPublic)
                PickemsHaptics.success()
                dismiss()
            } catch {
                appState.groupService.errorMessage = error.localizedDescription
            }
            isSaving = false
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

    private var customDeadlineDate: Date {
        var components = DateComponents()
        components.hour = rules.customDeadlineHour
        components.minute = rules.customDeadlineMinute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func updateCustomDeadline(from date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        rules.customDeadlineHour = components.hour ?? 18
        rules.customDeadlineMinute = components.minute ?? 0
    }
}
