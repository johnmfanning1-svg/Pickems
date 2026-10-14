import SwiftUI

/// Commissioner sets or extends the spread-pick deadline, and can reopen a locked week.
struct PickDeadlineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    let weekLabel: String
    var onSave: (
        _ groupId: String,
        _ weekId: String,
        _ isRollingLock: Bool,
        _ deadline: Date,
        _ reopenWeek: Bool,
        _ unlockMemberPicks: Bool
    ) -> Void
    var onLockRemainingNow: ((_ groupId: String, _ weekId: String) -> Void)? = nil

    @State private var deadline: Date
    @State private var unlockMemberPicks: Bool
    /// Frozen when the sheet is first created. A later league switch must not retarget Save.
    @State private var groupId: String
    @State private var weekId: String
    @State private var weekStatus: WeekStatus
    @State private var isPastDeadline: Bool
    @State private var isRollingLock: Bool

    private var needsReopen: Bool {
        weekStatus == .locked
    }

    init(
        groupId: String,
        weekId: String,
        weekLabel: String,
        weekStatus: WeekStatus,
        initialDeadline: Date?,
        isPastDeadline: Bool,
        isRollingLock: Bool = false,
        onLockRemainingNow: ((_ groupId: String, _ weekId: String) -> Void)? = nil,
        onSave: @escaping (
            _ groupId: String,
            _ weekId: String,
            _ isRollingLock: Bool,
            _ deadline: Date,
            _ reopenWeek: Bool,
            _ unlockMemberPicks: Bool
        ) -> Void
    ) {
        self.weekLabel = weekLabel
        self.onLockRemainingNow = onLockRemainingNow
        self.onSave = onSave
        let defaultDeadline = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let seed = initialDeadline.flatMap { $0 > Date() ? $0 : nil } ?? defaultDeadline
        _deadline = State(initialValue: seed)
        _unlockMemberPicks = State(initialValue: isPastDeadline || weekStatus == .locked)
        _groupId = State(initialValue: groupId)
        _weekId = State(initialValue: weekId)
        _weekStatus = State(initialValue: weekStatus)
        _isPastDeadline = State(initialValue: isPastDeadline)
        _isRollingLock = State(initialValue: isRollingLock)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        isRollingLock ? "Lock remaining at" : "Pickems deadline",
                        selection: $deadline,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .listRowBackground(PickemsColors.cardBackground)

                    if isRollingLock, weekStatus == .picking, let onLockRemainingNow {
                        Button("Lock remaining now") {
                            onLockRemainingNow(groupId, weekId)
                            dismiss()
                        }
                        .listRowBackground(PickemsColors.cardBackground)
                    }

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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(needsReopen ? "Reopen" : "Save") {
                        onSave(groupId, weekId, isRollingLock, deadline, needsReopen, unlockMemberPicks)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accent)
                }
            }
        }
    }

    private var navigationTitle: String {
        if needsReopen { return "Reopen Pickems" }
        if isRollingLock { return "Lock Remaining" }
        return "Pickems Deadline"
    }

    private var footerText: String {
        if isRollingLock {
            if needsReopen {
                return "Moves this week back to Pickems. Games that already kicked off stay locked. Optionally unlocks member submissions so they can edit remaining games."
            }
            if isPastDeadline {
                return "Sets when remaining open games lock. Games that already started stay locked."
            }
            return "Lock remaining open games at this time. Each game that already kicked off stays locked."
        }
        if needsReopen {
            return "Moves this week back to Pickems with your new deadline. Optionally unlocks member submissions so they can edit again."
        }
        if isPastDeadline {
            return "Extends the lock time so members can submit or edit again. Turn on Unlock to clear submitted locks."
        }
        return "Overrides the automatic first-kickoff lock for this week."
    }
}
