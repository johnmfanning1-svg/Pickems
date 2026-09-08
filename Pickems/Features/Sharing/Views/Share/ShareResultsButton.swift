import SwiftUI

struct ShareResultsButton: View {
    let source: ShareSource
    @EnvironmentObject private var xAuthService: XAuthService
    @Environment(\.themePalette) private var theme
    @State private var showShareSheet = false

    var body: some View {
        Button {
            showShareSheet = true
        } label: {
            Label(source.ctaTitle, systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
        .accessibilityLabel("Share results")
        .accessibilityValue(source.ctaTitle)
        .sheet(isPresented: $showShareSheet) {
            ShareResultsSheet(source: source)
                .environmentObject(xAuthService)
                .environment(\.themePalette, theme)
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
