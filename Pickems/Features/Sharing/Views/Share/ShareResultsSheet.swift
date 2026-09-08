import SwiftUI

struct ShareResultsSheet: View {
    let source: ShareSource

    @EnvironmentObject private var xAuthService: XAuthService
    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var tone: ShareTone = .auto
    @State private var shareImage: UIImage?
    @State private var showActivitySheet = false
    @State private var showMessageComposer = false
    @State private var isPosting = false
    @State private var showSuccess = false
    @State private var copied = false
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
                VStack(alignment: .leading, spacing: 22) {
                    ScaledShareCardPreview(result: resolvedResult, palette: theme)
                        .padding(.horizontal)

                    tonePicker
                        .padding(.horizontal)

                    messagePreview
                        .padding(.horizontal)

                    actions
                        .padding(.horizontal)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(PickemsColors.lost)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .pickemsScreenBackground()
            .navigationTitle("Share Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .onAppear { refreshImage() }
            .onChange(of: tone) { _, _ in refreshImage() }
            .sheet(isPresented: $showMessageComposer) {
                MessageComposeView(
                    body: resolvedResult.messageText,
                    image: shareImage,
                    fileName: resolvedResult.shareImageFileName
                )
            }
            .sheet(isPresented: $showActivitySheet) {
                ActivityView(items: shareService.shareSheetItems(for: resolvedResult, image: shareImage))
            }
            .alert("Posted to X", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your results are live.")
            }
        }
    }

    private var tonePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tone")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
            HStack(spacing: 8) {
                ForEach(ShareTone.allCases) { option in
                    Button {
                        tone = option
                        PickemsHaptics.selection()
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(tone == option ? theme.onAccent : PickemsColors.textPrimary)
                            .background(
                                tone == option ? theme.accent : PickemsColors.cardBackground,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tone == option ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Share tone")
        }
    }

    private var messagePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = resolvedResult.messageText
                    copied = true
                    PickemsHaptics.success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
            }
            Text(resolvedResult.messageText)
                .font(.body)
                .foregroundStyle(PickemsColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Your card sends as a photo — the first thing they see is the record.")
                .font(.footnote)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .padding(16)
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                sendTextMessage()
            } label: {
                Label("Text Message", systemImage: "message.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)

            Button {
                refreshImage()
                showActivitySheet = true
            } label: {
                Label("Share to…", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)

            if AppConfig.isXSharingConfigured {
                Button {
                    shareService.openXIntent(for: resolvedResult)
                } label: {
                    Label("Share on X", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)

                if xAuthService.isConnected {
                    Button {
                        Task { await postDirectly() }
                    } label: {
                        if isPosting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Post directly to X", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isPosting)
                }
            }
        }
    }

    private func refreshImage() {
        shareImage = ShareCardRenderer.renderImage(for: resolvedResult, palette: theme)
    }

    private func sendTextMessage() {
        refreshImage()
        PickemsHaptics.selection()
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
