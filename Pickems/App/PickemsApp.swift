import SwiftUI

@main
struct PickemsApp: App {
    var body: some Scene {
        WindowGroup {
            SmackTalkBootstrap {
                SharingBootstrap {
                    RootView()
                }
            }
        }
    }
}
