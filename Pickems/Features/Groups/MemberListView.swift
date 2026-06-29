import SwiftUI

struct MemberListView: View {
    @Environment(AppState.self) private var appState

    private var sortedMembers: [GroupMember] {
        appState.groupService.members.sorted {
            if $0.seasonWins != $1.seasonWins { return $0.seasonWins > $1.seasonWins }
            return $0.battingAverage > $1.battingAverage
        }
    }

    var body: some View {
        List {
            if sortedMembers.isEmpty {
                ContentUnavailableView(
                    "No Members",
                    systemImage: "person.3",
                    description: Text("Members appear here once they join the group.")
                )
            } else {
                Section {
                    ForEach(sortedMembers) { member in
                        MemberRow(
                            member: member,
                            isCommissioner: member.id == appState.groupService.selectedGroup?.commissionerId
                        )
                    }
                } header: {
                    if let group = appState.groupService.selectedGroup {
                        Text("\(group.memberCount) members in \(group.name)")
                    }
                }
            }
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(PickemsColors.background)
    }
}

struct MemberRow: View {
    let member: GroupMember
    let isCommissioner: Bool

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(
                initials: String(member.displayName.prefix(2)).uppercased(),
                colorHex: member.avatarColorHex,
                size: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.headline)
                        .foregroundStyle(PickemsColors.textPrimary)
                    if isCommissioner {
                        Text("Commissioner")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PickemsColors.accent.opacity(0.25))
                            .foregroundStyle(PickemsColors.accent)
                            .clipShape(Capsule())
                    }
                }
                Text("Joined \(member.joinedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(member.seasonWins)-\(member.seasonLosses)")
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(String(format: "%.3f", member.battingAverage))
                    .font(.caption2)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(PickemsColors.cardBackground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let role = isCommissioner ? ", commissioner" : ""
        return "\(member.displayName)\(role). Season record \(member.seasonWins) wins, \(member.seasonLosses) losses. Batting average \(String(format: "%.3f", member.battingAverage))"
    }
}
