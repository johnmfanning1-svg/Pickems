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
                .tabItem { Label("Leagues", systemImage: "trophy.fill") }
                .tag(AppTab.leagues)
                .accessibilityHint("League info, leaderboards, members, and chat")

            SelectionsView()
                .tabItem { Label("Selections", systemImage: "american.football.fill") }
                .tag(AppTab.selections)
                .accessibilityHint("Choose this week's games for your league")

            PickemsTabView()
                .tabItem { Label("Pickems", systemImage: "checkmark.circle.fill") }
                .tag(AppTab.pickems)
                .accessibilityHint("Pick who covers the spread")

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(AppTab.profile)
                .accessibilityHint("Display name, favorite team, and notification settings")
        }
        .tint(theme.accent)
        .onChange(of: appState.groupService.groups.map(\.id)) { _, _ in
            appState.publishSurfaces()
        }
    }
}

struct SelectionsView: View {
    var body: some View {
        PicksView(kind: .selections)
    }
}

struct PickemsTabView: View {
    var body: some View {
        PicksView(kind: .pickems)
    }
}
