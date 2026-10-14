import SwiftUI

/// Commissioner sets when member nominations must finish for the current week.
struct SelectionDeadlineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    let weekLabel: String
    let initialDeadline: Date?
    var onSave: (_ groupId: String, _ weekId: String, _ deadline: Date) -> Void

    @State private var deadline: Date
    /// Frozen when the sheet is first created. A later league switch must not retarget Save.
    @State private var groupId: String
    @State private var weekId: String

    init(
        groupId: String,
        weekId: String,
        weekLabel: String,
        initialDeadline: Date?,
        onSave: @escaping (_ groupId: String, _ weekId: String, _ deadline: Date) -> Void
    ) {
        self.weekLabel = weekLabel
        self.initialDeadline = initialDeadline
        self.onSave = onSave
        let defaultDeadline = Calendar.current.date(byAdding: .hour, value: 48, to: Date()) ?? Date()
        _deadline = State(initialValue: initialDeadline ?? defaultDeadline)
        _groupId = State(initialValue: groupId)
        _weekId = State(initialValue: weekId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Selection deadline",
                        selection: $deadline,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .listRowBackground(PickemsColors.cardBackground)
                } header: {
                    HStack {
                        Text(weekLabel)
                        Spacer()
                        HelpInfoButton(topic: PickemsHelp.selectionDeadline)
                    }
                } footer: {
                    Text("Members can make Selections until this time. Afterward you can fill remaining games or open the week with fewer.")
                }
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle("Selection Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(groupId, weekId, deadline)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
                }
            }
        }
    }
}
