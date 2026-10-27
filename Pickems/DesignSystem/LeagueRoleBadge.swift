import SwiftUI

/// Short OC / DC capsule, matching the commissioner capsule on member rows.
struct LeagueRoleBadge: View {
    @Environment(\.themePalette) private var theme

    let role: LeagueCoordinatorRole

    var body: some View {
        Text(role.shortTitle)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.accent.opacity(0.25))
            .foregroundStyle(theme.accent)
            .clipShape(Capsule())
            .accessibilityLabel(role.accessibilityLabel)
    }
}
