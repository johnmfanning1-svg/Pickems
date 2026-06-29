import SwiftUI

@main
struct PickemsApp: App {
    @StateObject private var xAuthService = XAuthService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(xAuthService)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            WeeklyStandingsView()
                .tabItem {
                    Label("This Week", systemImage: "calendar")
                }

            SeasonStandingsView()
                .tabItem {
                    Label("Season", systemImage: "trophy")
                }

            XConnectionSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(XAuthService())
    }
}
#endif
