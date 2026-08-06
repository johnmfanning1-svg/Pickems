import SwiftUI

/// Commissioner sets when member nominations must finish for the current week.
struct SelectionDeadlineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    let weekLabel: String
    let initialDeadline: Date?
    var onSave: (Date) -> Void

    @State private var deadline: Date

    init(weekLabel: String, initialDeadline: Date?, onSave: @escaping (Date) -> Void) {
        self.weekLabel = weekLabel
        self.initialDeadline = initialDeadline
        self.onSave = onSave
        let defaultDeadline = Calendar.current.date(byAdding: .hour, value: 48, to: Date()) ?? Date()
        _deadline = State(initialValue: initialDeadline ?? defaultDeadline)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Nomination deadline",
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
                    Text("Members can nominate until this time. Afterward you can fill remaining games or open the week with fewer.")
                }
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle("Nomination Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(deadline)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
                }
            }
        }
    }
}
