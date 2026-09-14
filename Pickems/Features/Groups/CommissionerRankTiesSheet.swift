import SwiftUI

struct TieRankDraft: Identifiable, Equatable {
    let entries: [StandingEntry]

    var id: String {
        entries.map(\.id).sorted().joined(separator: "|")
    }
}

/// Commissioner Override: reorder a deadlock, then save the full ranking for this week.
struct CommissionerRankTiesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    let weekLabel: String
    var onSave: ([String]) async throws -> Void

    @State private var ordered: [StandingEntry]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        weekLabel: String,
        entries: [StandingEntry],
        onSave: @escaping ([String]) async throws -> Void
    ) {
        self.weekLabel = weekLabel
        self.onSave = onSave
        _ordered = State(initialValue: entries)
    }

    private var recordLabel: String {
        let records = Set(ordered.map { "\($0.weeklyWins)–\($0.weeklyLosses)" })
        if records.count == 1, let record = records.first {
            return record
        }
        let wins = ordered.first?.weeklyWins ?? 0
        return "\(wins) win\(wins == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ordered) { entry in
                        rankRow(place: place(of: entry), entry: entry)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                    .onMove(perform: move)
                    .deleteDisabled(true)
                } header: {
                    Text("Top of the list ranks higher this week.")
                } footer: {
                    Text("Drag the handles to set 1st through last among this group. Saves for \(weekLabel) only.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(PickemsColors.warning)
                            .listRowBackground(PickemsColors.cardBackground)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .pickemsScreenBackground()
            .navigationTitle("Rank \(recordLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.accent)
                        .disabled(isSaving || ordered.count < 2)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func place(of entry: StandingEntry) -> Int {
        (ordered.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1
    }

    private func rankRow(place: Int, entry: StandingEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(place)")
                .font(PickemsTypography.display(18))
                .foregroundStyle(place == 1 ? theme.accent : PickemsColors.textSecondary)
                .frame(width: 28, alignment: .leading)
                .accessibilityHidden(true)

            InitialsAvatar(
                initials: String(entry.displayName.prefix(2)).uppercased(),
                colorHex: entry.avatarColorHex,
                imageURL: entry.avatarImageURL,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .foregroundStyle(PickemsColors.textPrimary)
                Text("\(entry.weeklyWins)–\(entry.weeklyLosses)")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(place == 1 ? "1st" : place == 2 ? "2nd" : place == 3 ? "3rd" : "\(place)th"), \(entry.displayName), \(entry.weeklyWins) to \(entry.weeklyLosses)"
        )
        .accessibilityHint("Drag to change This Week rank in this group.")
    }

    private func move(from offsets: IndexSet, to offset: Int) {
        ordered.move(fromOffsets: offsets, toOffset: offset)
        PickemsHaptics.selection()
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await onSave(ordered.map(\.id))
                PickemsHaptics.success()
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error, context: .write)
                    ?? error.localizedDescription
                PickemsHaptics.warning()
            }
        }
    }
}
