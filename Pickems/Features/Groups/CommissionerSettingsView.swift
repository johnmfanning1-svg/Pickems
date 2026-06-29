import SwiftUI

struct CommissionerSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let group: PickemGroup
    @State private var rules: GroupRules
    @State private var isSaving = false

    init(group: PickemGroup) {
        self.group = group
        _rules = State(initialValue: group.rules)
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
                } header: {
                    sectionHeader("Deadlines & Ties", help: PickemsHelp.pickDeadline)
                } footer: {
                    Text("Changes apply to future weeks. Existing locked weeks are not affected.")
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
                PickemsHaptics.success()
                dismiss()
            } catch {
                appState.groupService.errorMessage = error.localizedDescription
            }
            isSaving = false
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
