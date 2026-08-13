import SwiftUI

/// Commissioner sets or extends the spread-pick deadline, and can reopen a locked week.
struct PickDeadlineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    let weekLabel: String
    let weekStatus: WeekStatus
    let initialDeadline: Date?
    let isPastDeadline: Bool
    var onSave: (_ deadline: Date, _ reopenWeek: Bool, _ unlockMemberPicks: Bool) -> Void

    @State private var deadline: Date
    @State private var unlockMemberPicks: Bool

    private var needsReopen: Bool {
        weekStatus == .locked
    }

    init(
        weekLabel: String,
        weekStatus: WeekStatus,
        initialDeadline: Date?,
        isPastDeadline: Bool,
        onSave: @escaping (_ deadline: Date, _ reopenWeek: Bool, _ unlockMemberPicks: Bool) -> Void
    ) {
        self.weekLabel = weekLabel
        self.weekStatus = weekStatus
        self.initialDeadline = initialDeadline
        self.isPastDeadline = isPastDeadline
        self.onSave = onSave
        let defaultDeadline = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let seed = initialDeadline.flatMap { $0 > Date() ? $0 : nil } ?? defaultDeadline
        _deadline = State(initialValue: seed)
        _unlockMemberPicks = State(initialValue: isPastDeadline || weekStatus == .locked)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Pickems deadline",
                        selection: $deadline,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .listRowBackground(PickemsColors.cardBackground)

                    if isPastDeadline || needsReopen {
                        Toggle("Unlock submitted Pickems", isOn: $unlockMemberPicks)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                } header: {
                    HStack {
                        Text(weekLabel)
                        Spacer()
                        HelpInfoButton(topic: PickemsHelp.pickDeadline)
                    }
                } footer: {
                    Text(footerText)
                }
            }
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle(needsReopen ? "Reopen Pickems" : "Pickems Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(needsReopen ? "Reopen" : "Save") {
                        onSave(deadline, needsReopen, unlockMemberPicks)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
                }
            }
        }
    }

    private var footerText: String {
        if needsReopen {
            return "Moves this week back to Pickems with your new deadline. Optionally unlocks member submissions so they can edit again."
        }
        if isPastDeadline {
            return "Extends the lock time so members can submit or edit again. Turn on Unlock to clear submitted locks."
        }
        return "Overrides the automatic first-kickoff lock for this week."
    }
}
