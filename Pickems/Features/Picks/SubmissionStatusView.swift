import SwiftUI

struct SubmissionStatusView: View {
    let members: [GroupMember]
    let submissions: [PickSubmission]

    private var submittedIds: Set<String> {
        Set(submissions.filter(\.isLocked).map(\.userId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PickemsSectionHeader(
                title: "Submission Status",
                subtitle: "\(submittedIds.count) of \(members.count) submitted"
            )

            ForEach(members) { member in
                HStack {
                    InitialsAvatar(
                        initials: String(member.displayName.prefix(2)).uppercased(),
                        colorHex: member.avatarColorHex,
                        size: 32
                    )
                    Text(member.displayName)
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textPrimary)
                    Spacer()
                    if submittedIds.contains(member.id) {
                        Label("In", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.success)
                    } else {
                        Label("Pending", systemImage: "clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.warning)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
