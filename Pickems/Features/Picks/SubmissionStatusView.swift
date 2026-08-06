import SwiftUI

struct SubmissionStatusView: View {
    let members: [GroupMember]
    let submissions: [PickSubmission]
    var slateSize: Int = 0

    private var submittedIds: Set<String> {
        Set(members.map(\.id).filter(isSubmitted))
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
                        initials: member.initials,
                        colorHex: member.avatarColorHex,
                        imageURL: member.avatarImageURL,
                        size: 32
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName)
                            .font(.subheadline)
                            .foregroundStyle(PickemsColors.textPrimary)
                        let made = pickCount(for: member.id)
                        if slateSize > 0 {
                            Text("\(made)/\(slateSize)")
                                .font(.caption2)
                                .foregroundStyle(PickemsColors.textSecondary)
                        }
                    }
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

    private func submission(for userId: String) -> PickSubmission? {
        submissions.first { $0.userId == userId }
    }

    private func pickCount(for userId: String) -> Int {
        let sub = submission(for: userId)
        if let count = sub?.pickCount, count > 0 { return count }
        if sub?.isLocked == true, slateSize > 0 { return slateSize }
        return sub?.pickCount ?? 0
    }

    private func isSubmitted(_ userId: String) -> Bool {
        guard let sub = submission(for: userId) else { return false }
        if sub.isLocked { return true }
        return slateSize > 0 && sub.pickCount >= slateSize
    }
}
