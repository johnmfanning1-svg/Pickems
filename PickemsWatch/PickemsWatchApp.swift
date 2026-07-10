import WatchKit
import SwiftUI
import WidgetKit

/// watchOS complications + glance standings from the shared App Group.
@main
struct PickemsWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchStandingsView()
        }
    }
}

struct WatchStandingsView: View {
    @State private var snapshot = PickemsAppGroup.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot {
                Text(snapshot.groupName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("#\(snapshot.rank)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Week \(snapshot.weekNumber): \(snapshot.weeklyRecord)")
                    .font(.caption)
                Text("Season \(snapshot.seasonRecord)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open Pickems on iPhone to sync standings.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .onAppear { snapshot = PickemsAppGroup.load() }
    }
}
