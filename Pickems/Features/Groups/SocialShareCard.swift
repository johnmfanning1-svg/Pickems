import SwiftUI

struct SocialShareCard: View {
    let group: PickemGroup
    let standings: GroupStandings?
    var includeInviteCode: Bool = true
    @Environment(\.themePalette) private var theme

    var body: some View {
        ShareLink(item: shareText) {
            Label("Share League Card", systemImage: "photo")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(PickemsColors.cardBackground)
                .foregroundStyle(theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private var shareText: String {
        var lines = ["🏈 \(group.name)"]
        if includeInviteCode {
            lines.append("Invite code: \(group.inviteCode)")
            lines.append("Join: pickems://join?code=\(group.inviteCode)")
        }
        if let leader = standings?.entries.first {
            lines.append("Leader: \(leader.displayName) (\(leader.weeklyWins)-\(leader.weeklyLosses))")
        }
        return lines.joined(separator: "\n")
    }
}
