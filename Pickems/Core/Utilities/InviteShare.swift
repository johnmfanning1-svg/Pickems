import SwiftUI

enum InviteShare {
    static func message(for group: PickemGroup) -> String {
        """
        Join \(group.name) on Pickems!

        Invite code: \(group.inviteCode)

        1. Download Pickems from the App Store (TestFlight link coming soon)
        2. Sign in with Apple
        3. Tap Join Group and enter the code above

        Let's run it this CFB season!
        """
    }

    static func url(for group: PickemGroup) -> URL? {
        URL(string: "pickems://join?code=\(group.inviteCode)")
    }

    static func universalURL(for group: PickemGroup) -> URL? {
        URL(string: "https://pickems.app/join?code=\(group.inviteCode)")
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct InviteShareButton: View {
    let group: PickemGroup
    @Environment(\.themePalette) private var theme
    @State private var showShareSheet = false

    var body: some View {
        Button {
            PickemsHaptics.lightImpact()
            showShareSheet = true
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
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
                .presentationDetents([.medium, .large])
        }
    }

    private var shareItems: [Any] {
        var items: [Any] = [InviteShare.message(for: group)]
        if let url = InviteShare.universalURL(for: group) ?? InviteShare.url(for: group) {
            items.append(url)
        }
        return items
    }
}
