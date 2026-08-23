import SwiftUI

struct SubmissionStatusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var rows: [SubmissionRosterRow] {
        SubmissionRoster.rows(
            members: appState.groupService.members,
            submissions: appState.pickService.submissions,
            slateSize: appState.pickService.slateGames.count
        )
    }

    private var currentUserId: String? {
        appState.authService.currentUser?.id ?? appState.authService.currentUserId
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "No Members",
                        systemImage: "person.3",
                        description: Text("League members will appear here.")
                    )
                } else {
                    rosterList
                }
            }
            .pickemsScreenBackground()
            .navigationTitle("Who's in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private var rosterList: some View {
        let submitted = SubmissionRoster.submittedCount(in: rows)
        return List {
            Section {
                ForEach(rows) { row in
                    rosterRow(row)
                        .listRowBackground(PickemsColors.cardBackground)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
            } header: {
                Text("\(submitted) of \(rows.count) submitted")
                    .foregroundStyle(PickemsColors.textSecondary)
            } footer: {
                Text("Counts only. Who they picked stays hidden until the first kickoff or an early lock.")
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func rosterRow(_ row: SubmissionRosterRow) -> some View {
        let isYou = row.id == currentUserId
        return HStack(spacing: 12) {
            InitialsAvatar(
                initials: row.initials,
                colorHex: row.avatarColorHex,
                imageURL: row.avatarImageURL,
                size: 36
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isYou ? "\(row.displayName) (You)" : row.displayName)
                        .font(.subheadline.weight(isYou ? .semibold : .regular))
                        .foregroundStyle(PickemsColors.textPrimary)
                        .lineLimit(1)
                }
                Text(countLabel(for: row))
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            StatusBadge(text: row.status.label, color: badgeColor(for: row.status))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: row, isYou: isYou))
    }

    private func countLabel(for row: SubmissionRosterRow) -> String {
        if row.total > 0 {
            return "\(row.made) of \(row.total) Pickems"
        }
        return "No slate yet"
    }

    private func badgeColor(for status: SubmissionRosterStatus) -> Color {
        switch status {
        case .submitted: return PickemsColors.success
        case .inProgress: return PickemsColors.covering
        case .notStarted: return PickemsColors.warning
        }
    }

    private func accessibilityLabel(for row: SubmissionRosterRow, isYou: Bool) -> String {
        let name = isYou ? "You, \(row.displayName)" : row.displayName
        return "\(name), \(countLabel(for: row)), \(row.status.label)"
    }
}
