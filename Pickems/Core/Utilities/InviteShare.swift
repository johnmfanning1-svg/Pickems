import SwiftUI

enum InviteShare {
    static func message(for group: PickemGroup) -> String {
        let link = universalURL(for: group)?.absoluteString
            ?? "\(AppConfig.inviteJoinBaseURL)/join?code=\(group.inviteCode)"
        return """
        Join \(group.name) on Pickems!

        \(link)

        Invite code: \(group.inviteCode)

        1. Download Pickems: \(AppConfig.appStoreURL)
        2. Sign in with Apple or email
        3. Tap the link above, or tap Join League and enter the code

        Let's run it this CFB season!
        """
    }

    static func url(for group: PickemGroup) -> URL? {
        URL(string: "pickems://join?code=\(group.inviteCode)")
    }

    static func universalURL(for group: PickemGroup) -> URL? {
        URL(string: "\(AppConfig.inviteJoinBaseURL)/join?code=\(group.inviteCode)")
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct CommissionerOnlyInviteNotice: View {
    var commissionerName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title3)
                .foregroundStyle(PickemsColors.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ask the commissioner to invite")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        if let commissionerName, !commissionerName.isEmpty {
            return "Only \(commissionerName) can invite people to this league. Ask them to share the invite from Invite Friends."
        }
        return "Only the commissioner can invite people to this league. Ask them to share the invite from Invite Friends."
    }
}

struct InviteShareButton: View {
    let group: PickemGroup
    @Environment(\.themePalette) private var theme
    @Environment(\.helpPresenter) private var helpPresenter
    @State private var showShareSheet = false

    var body: some View {
        if helpPresenter == nil {
            inviteButton
                .sheet(isPresented: $showShareSheet) { // presentation-ok: fallback when no screen presenter
                    fallbackShareSheet
                }
        } else {
            inviteButton
        }
    }

    private var inviteButton: some View {
        Button {
            presentInvite()
        } label: {
            Label("Invite Friends", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(theme.accent)
                .foregroundStyle(theme.onAccent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Invite Friends")
        .accessibilityHint("Share invite code \(group.inviteCode) for \(group.name)")
    }

    private func presentInvite() {
        PickemsHaptics.lightImpact()
        let items = shareItems
        let modal = ScreenModal.shareSheet(items: items, id: UUID())
        PickemsPresentation.afterTap {
            if let helpPresenter {
                helpPresenter.modal = modal
            } else {
                showShareSheet = true
            }
        }
    }

    private var fallbackShareSheet: some View {
        ShareSheet(items: shareItems)
            .presentationDetents([.medium, .large])
    }

    private var shareItems: [Any] {
        var items: [Any] = [InviteShare.message(for: group)]
        if let url = InviteShare.universalURL(for: group) ?? InviteShare.url(for: group) {
            items.append(url)
        }
        return items
    }
}
