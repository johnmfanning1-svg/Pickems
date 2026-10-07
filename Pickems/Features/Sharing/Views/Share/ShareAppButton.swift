import SwiftUI

struct ShareAppButton: View {
    var leagueName: String? = nil
    var label: String = "Invite Friends"

    @EnvironmentObject private var xAuthService: XAuthService
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
            presentApp()
        } label: {
            Label(label, systemImage: "person.2.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func presentApp() {
        let modal = ScreenModal.shareApp(leagueName: leagueName, xAuthService, id: UUID())
        PickemsPresentation.afterTap {
            if let helpPresenter {
                helpPresenter.modal = modal
            } else {
                showShareSheet = true
            }
        }
    }

    private var fallbackSheet: some View {
        ShareAppSheet(leagueName: leagueName)
            .environmentObject(xAuthService)
    }
}

#if DEBUG
struct ShareAppButton_Previews: PreviewProvider {
    static var previews: some View {
        ShareAppButton(leagueName: "Fannypack")
            .environmentObject(XAuthService())
            .padding()
    }
}
#endif
