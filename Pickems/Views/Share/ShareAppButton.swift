import SwiftUI

struct ShareAppButton: View {
    var leagueName: String? = nil
    var label: String = "Invite Friends"

    @EnvironmentObject private var xAuthService: XAuthService
    @State private var showShareSheet = false

    var body: some View {
        Button {
            showShareSheet = true
        } label: {
            Label(label, systemImage: "person.2.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showShareSheet) {
            ShareAppSheet(leagueName: leagueName)
                .environmentObject(xAuthService)
        }
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
