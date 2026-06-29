import SwiftUI

struct WeeklyStandingsView: View {
    @State private var result = DemoData.weeklyResult

    var body: some View {
        NavigationStack {
            List {
                Section("Your Week") {
                    LabeledContent("League", value: result.leagueName)
                    LabeledContent("Week", value: "\(result.week)")
                    LabeledContent("Record", value: result.recordText)
                    LabeledContent("Rank", value: result.placementText)
                    if let delta = result.tiebreakerDelta {
                        LabeledContent("Tiebreaker", value: "\(delta >= 0 ? "+" : "")\(delta)")
                    }
                }

                Section {
                    ShareResultsButton(source: .weekly(result))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Share your weekly results to X and drive friends to Pickems.")
                }
            }
            .navigationTitle("Week \(result.week)")
        }
    }
}

#if DEBUG
struct WeeklyStandingsView_Previews: PreviewProvider {
    static var previews: some View {
        WeeklyStandingsView()
            .environmentObject(XAuthService())
    }
}
#endif
