import SwiftUI

struct XConnectionSettingsView: View {
    @EnvironmentObject private var xAuthService: XAuthService
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let username = xAuthService.connectedUsername {
                        LabeledContent("Connected as", value: "@\(username)")
                    } else if xAuthService.isConnected {
                        LabeledContent("Status", value: "Connected")
                    } else {
                        Text("Connect X to post results directly from Pickems without leaving the app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if xAuthService.isConnected {
                        Button("Disconnect X", role: .destructive) {
                            xAuthService.disconnect()
                        }
                    } else {
                        Button {
                            Task { await connect() }
                        } label: {
                            if xAuthService.isConnecting {
                                HStack {
                                    ProgressView()
                                    Text("Connecting…")
                                }
                            } else {
                                Label("Connect X Account", systemImage: "link")
                            }
                        }
                        .disabled(xAuthService.isConnecting)
                    }
                } header: {
                    Text("X Integration")
                } footer: {
                    Text("Requires an X Developer app with OAuth 2.0 PKCE enabled. Set your Client ID in AppConfig.swift and register the \(AppConfig.xRedirectURI) callback URL.")
                }

                Section("Promotion") {
                    LabeledContent("App URL", value: AppConfig.appPromoURL)
                    LabeledContent("Hashtags", value: "\(AppConfig.cfbHashtag) \(AppConfig.appHashtag)")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func connect() async {
        errorMessage = nil
        do {
            try await xAuthService.connect()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
struct XConnectionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        XConnectionSettingsView()
            .environmentObject(XAuthService())
    }
}
#endif
