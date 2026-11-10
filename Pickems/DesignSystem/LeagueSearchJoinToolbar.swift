import SwiftUI

/// Leading nav-bar control for finding a league.
///
/// Opens the existing join sheet (`JoinGroupSheet` via `AppSheet.joinGroup`),
/// the same presentation as Home's "Join / Search" and the Leagues "Join League"
/// row. It stays in the toolbar so an in-content Home header can sit under it.
enum LeagueSearchJoin {
    static let systemImage = "magnifyingglass"
    static let accessibilityLabel = "Search or join a league"
    static let accessibilityHint = "Enter an invite code, or browse public leagues"
    static let sheet: AppSheet = .joinGroup
}

struct LeagueSearchJoinToolbarButton: View {
    var present: (AppSheet) -> Void

    var body: some View {
        Button {
            PickemsHaptics.lightImpact()
            PickemsPresentation.afterTap {
                present(LeagueSearchJoin.sheet)
            }
        } label: {
            Image(systemName: LeagueSearchJoin.systemImage)
                .font(.subheadline)
                .imageScale(.small)
                .foregroundStyle(PickemsColors.textSecondary)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .controlSize(.mini)
        .accessibilityLabel(LeagueSearchJoin.accessibilityLabel)
        .accessibilityHint(LeagueSearchJoin.accessibilityHint)
    }
}

/// Leading slot, matching the compact help control on the trailing side.
struct LeagueSearchJoinToolbarItem: ToolbarContent {
    var present: (AppSheet) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            LeagueSearchJoinToolbarButton(present: present)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
