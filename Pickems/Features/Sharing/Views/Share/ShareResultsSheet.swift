import SwiftUI

struct ShareResultsSheet: View {
    let source: ShareSource

    @EnvironmentObject private var xAuthService: XAuthService
    @Environment(\.dismiss) private var dismiss

    @State private var tone: ShareTone = .auto
    @State private var shareImage: UIImage?
    @State private var showActivitySheet = false
    @State private var showMessageComposer = false
    @State private var isPosting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    private var shareService: XShareService {
        XShareService(authService: xAuthService)
    }

    private var resolvedResult: ShareableResult {
        source.makeShareableResult(tone: tone)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ResultsShareCard(result: resolvedResult)
                        .frame(height: 220)
                        .padding(.horizontal)

                    Picker("Tone", selection: $tone) {
                        ForEach(ShareTone.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(resolvedResult.messageText)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button {
                            shareService.openXIntent(for: resolvedResult)
                        } label: {
                            Label("Share on X", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black)

                        Button {
                            sendTextMessage()
                        } label: {
                            Label("Text Message", systemImage: "message.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button {
                            shareImage = ShareCardRenderer.renderImage(for: resolvedResult)
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
                                    Label("Post Directly to X", systemImage: "paperplane.fill")
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
            .navigationTitle("Share Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                shareImage = ShareCardRenderer.renderImage(for: resolvedResult)
            }
            .onChange(of: tone) { _, _ in
                shareImage = ShareCardRenderer.renderImage(for: resolvedResult)
            }
            .sheet(isPresented: $showMessageComposer) {
                MessageComposeView(
                    body: resolvedResult.messageText,
                    image: shareImage
                )
            }
            .sheet(isPresented: $showActivitySheet) {
                ActivityView(items: shareService.shareSheetItems(for: resolvedResult, image: shareImage))
            }
            .alert("Posted to X", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your results are live. Go dunk on the timeline.")
            }
        }
    }

    private func sendTextMessage() {
        shareImage = ShareCardRenderer.renderImage(for: resolvedResult)

        if MessageShareService.canSendText {
            showMessageComposer = true
        } else {
            MessageShareService.openSMSFallback(body: resolvedResult.messageText)
        }
    }

    private func postDirectly() async {
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            try await shareService.postDirectly(for: resolvedResult)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
struct ShareResultsSheet_Previews: PreviewProvider {
    static var previews: some View {
        ShareResultsSheet(source: .weekly(DemoData.weeklyResult))
            .environmentObject(XAuthService())
    }
}
#endif
