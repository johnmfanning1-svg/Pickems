import SwiftUI

struct ShareResultsButton: View {
    let source: ShareSource
    @EnvironmentObject private var xAuthService: XAuthService
    @Environment(\.themePalette) private var theme
    @Environment(\.helpPresenter) private var helpPresenter
    @State private var showShareSheet = false

    var body: some View {
        if helpPresenter == nil {
            shareButton
                .sheet(isPresented: $showShareSheet) { // presentation-ok: fallback when no screen presenter
                    fallbackSheet
                }
        } else {
            shareButton
        }
    }

    private var shareButton: some View {
        Button {
            presentResults()
        } label: {
            Label(source.ctaTitle, systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
        .accessibilityLabel("Share results")
        .accessibilityValue(source.ctaTitle)
    }

    private func presentResults() {
        let modal = ScreenModal.shareResults(source, xAuthService, id: UUID())
        PickemsPresentation.afterTap {
            if let helpPresenter {
                helpPresenter.modal = modal
            } else {
                showShareSheet = true
            }
        }
    }

    private var fallbackSheet: some View {
        ShareResultsSheet(source: source)
            .environmentObject(xAuthService)
            .environment(\.themePalette, theme)
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
