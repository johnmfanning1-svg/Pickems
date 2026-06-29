import SwiftUI

struct ShareResultsButton: View {
    let source: ShareSource
    @EnvironmentObject private var xAuthService: XAuthService
    @State private var showShareSheet = false

    var body: some View {
        Button {
            showShareSheet = true
        } label: {
            Label("Share to X", systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.black)
        .sheet(isPresented: $showShareSheet) {
            ShareResultsSheet(source: source)
                .environmentObject(xAuthService)
        }
    }
}

#if DEBUG
struct ShareResultsButton_Previews: PreviewProvider {
    static var previews: some View {
        ShareResultsButton(source: .weekly(DemoData.weeklyResult))
            .environmentObject(XAuthService())
            .padding()
    }
}
#endif
