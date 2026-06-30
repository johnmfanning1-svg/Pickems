import SwiftUI

/// Demo root view for the generated Xcode project.
/// Replace this with your real Pickems navigation when syncing locally.
struct RootView: View {
    var body: some View {
        TabView {
            WeeklyStandingsView()
                .tabItem {
                    Label("This Week", systemImage: "calendar")
                }

            SmackTalkTabView()
                .tabItem {
                    Label("Smack Talk", systemImage: "bubble.left.and.bubble.right.fill")
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
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        SmackTalkBootstrap {
            SharingBootstrap {
                RootView()
            }
        }
    }
}
#endif
