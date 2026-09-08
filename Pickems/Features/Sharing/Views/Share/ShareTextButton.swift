import SwiftUI

/// Text-only share for league recaps (no personal results card).
struct ShareTextButton: View {
    var title: String = "Share league recap"
    let text: String
    var groupId: String? = nil
    var weekId: String? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var showMessageComposer = false
    @State private var showActivitySheet = false
    @State private var sentToChat = false
    @State private var chatError: String?

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsLeagueChat: Bool {
        groupId != nil && appState.chatService.chatEnabled
    }

    private var fitsChat: Bool {
        !trimmed.isEmpty && trimmed.count <= ChatMessage.maxTextLength
    }

    private var canSendToChat: Bool {
        showsLeagueChat
            && fitsChat
            && !appState.chatService.isSending
            && appState.authService.currentUser != nil
            && !sentToChat
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsLeagueChat {
                leagueChatButton
            }

            if showsLeagueChat {
                textMessageButton
                    .buttonStyle(.bordered)
                    .tint(theme.accent)
            } else {
                textMessageButton
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
            }

            Button {
                showActivitySheet = true
            } label: {
                Label("Share to…", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(theme.accent)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .task {
            await appState.chatService.refreshRemoteConfig()
        }
        .onChange(of: text) { _, _ in
            sentToChat = false
            chatError = nil
        }
        .sheet(isPresented: $showMessageComposer) {
            MessageComposeView(body: text)
        }
        .sheet(isPresented: $showActivitySheet) {
            ActivityView(items: [text])
        }
    }

    private var leagueChatButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                sendToLeagueChat()
            } label: {
                if appState.chatService.isSending {
                    ProgressView()
                        .tint(theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                } else {
                    Label(
                        sentToChat ? "Sent to League chat" : "Send to League chat",
                        systemImage: sentToChat ? "checkmark.circle.fill" : "bubble.left.and.bubble.right.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(
                !fitsChat
                    || appState.chatService.isSending
                    || appState.authService.currentUser == nil
            )
            .allowsHitTesting(!sentToChat)
            .accessibilityLabel(sentToChat ? "Sent to League chat" : "Send to League chat")

            if !fitsChat, !trimmed.isEmpty {
                Text("League chat max is \(ChatMessage.maxTextLength) characters. Trim the recap or use Text Message.")
                    .font(.footnote)
                    .foregroundStyle(PickemsColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let chatError {
                Text(chatError)
                    .font(.footnote)
                    .foregroundStyle(PickemsColors.lost)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var textMessageButton: some View {
        Button {
            sendText()
        } label: {
            Label("Text Message", systemImage: "message.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
    }

    private func sendToLeagueChat() {
        guard canSendToChat,
              let groupId,
              let author = appState.authService.currentUser else { return }
        PickemsHaptics.lightImpact()
        chatError = nil
        Task {
            let sent = await appState.chatService.send(
                text: trimmed,
                groupId: groupId,
                weekId: weekId,
                author: author
            )
            if sent {
                sentToChat = true
                PickemsHaptics.success()
            } else {
                chatError = appState.chatService.errorMessage ?? "Couldn't send to League chat."
                PickemsHaptics.warning()
            }
        }
    }

    private func sendText() {
        PickemsHaptics.selection()
        if MessageShareService.canSendText {
            showMessageComposer = true
        } else {
            MessageShareService.openSMSFallback(body: text)
        }
    }
}
