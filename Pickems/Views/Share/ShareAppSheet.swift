import SwiftUI

struct ShareAppSheet: View {
    var leagueName: String? = nil

    @EnvironmentObject private var xAuthService: XAuthService
    @Environment(\.dismiss) private var dismiss

    @State private var showMessageComposer = false
    @State private var showActivitySheet = false
    @State private var isPosting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    private var shareService: XShareService {
        XShareService(authService: xAuthService)
    }

    private var messageText: String {
        AppShareContent.inviteMessage(leagueName: leagueName)
    }

    private var tweetText: String {
        AppShareContent.inviteTweet(leagueName: leagueName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Invite Friends", systemImage: "person.2.fill")
                            .font(.title2.weight(.bold))

                        Text("Share Pickems so your league can join, pick games, and talk trash all season.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(messageText)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button {
                            shareService.openXIntent(text: tweetText)
                        } label: {
                            Label("Share App on X", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)

                        Button {
                            sendTextMessage()
                        } label: {
                            Label("Text Invite", systemImage: "message.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button {
                            showActivitySheet = true
                        } label: {
                            Label("More Sharing Options", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        if xAuthService.isConnected {
                            Button {
                                Task { await postDirectly() }
                            } label: {
                                if isPosting {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("Post App Invite to X", systemImage: "paperplane.fill")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isPosting)
                        }
                    }
                    .padding(.horizontal)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Share Pickems")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showMessageComposer) {
                MessageComposeView(body: messageText)
            }
            .sheet(isPresented: $showActivitySheet) {
                ActivityView(items: shareService.shareSheetItems(text: messageText))
            }
            .alert("Posted to X", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your Pickems invite is live.")
            }
        }
    }

    private func sendTextMessage() {
        if MessageShareService.canSendText {
            showMessageComposer = true
        } else {
            MessageShareService.openSMSFallback(body: messageText)
        }
    }

    private func postDirectly() async {
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            try await shareService.postDirectly(text: tweetText)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
struct ShareAppSheet_Previews: PreviewProvider {
    static var previews: some View {
        ShareAppSheet(leagueName: "Fannypack")
            .environmentObject(XAuthService())
    }
}
#endif
