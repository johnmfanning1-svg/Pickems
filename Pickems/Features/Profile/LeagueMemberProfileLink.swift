import SwiftUI

/// Pushes this league's member profile. Use it on a name or avatar, not as a long-press.
struct LeagueMemberProfileLink<Label: View>: View {
    let userId: String
    var hint: String = "Opens league profile"
    @ViewBuilder var label: () -> Label

    var body: some View {
        NavigationLink {
            LeagueMemberProfileView(userId: userId)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }
}
