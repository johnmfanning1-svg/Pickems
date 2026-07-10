import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
                .accessibilityHint("Scores, quick actions, and standings preview")

            GroupsView()
                .tabItem { Label("Groups", systemImage: "person.3.fill") }
                .tag(AppTab.groups)
                .accessibilityHint("Your leagues, invites, and full leaderboard")

            PicksView()
                .tabItem { Label("Picks", systemImage: "checkmark.circle.fill") }
                .tag(AppTab.picks)
                .accessibilityHint("Nominate games and submit spread picks")

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(AppTab.profile)
                .accessibilityHint("Display name and notification settings")
        }
        .tint(theme.accent)
    }
}
