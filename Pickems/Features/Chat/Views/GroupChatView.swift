import SwiftUI

/// Group chat feed plus composer. One Firestore listener owns the newest 50
/// messages; older pages load on demand from the top of the thread.
struct GroupChatView: View {
    let group: PickemGroup

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    @State private var draft = ""
    @State private var moderationTarget: ChatMessage?
    @State private var showBlockedUsers = false
    @AppStorage("chat.guidelines.acknowledged") private var didAcknowledgeGuidelines = false

    private var chat: ChatService { appState.chatService }

    private var messages: [ChatMessage] { chat.visibleMessages }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedDraft.isEmpty
            && trimmedDraft.count <= ChatMessage.maxTextLength
            && !chat.isSending
    }

    var body: some View {
        Group {
            if chat.chatEnabled {
                chatContent
            } else {
                ContentUnavailableView(
                    "Chat Unavailable",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                    description: Text("Group chat is turned off right now. Check back soon.")
                )
            }
        }
        .pickemsScreenBackground()
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                chatMenu
            }
        }
        .sheet(item: $moderationTarget) { message in
            ChatModerationSheet(message: message)
                .pickemsEnvironment(appState)
        }
        .sheet(isPresented: $showBlockedUsers) {
            ChatBlockedUsersSheet(group: group)
                .pickemsEnvironment(appState)
        }
        .task(id: group.id) {
            guard let userId = appState.currentUserId else { return }
            await chat.refreshRemoteConfig()
            chat.loadLocalModerationState(userId: userId)
            chat.observe(groupId: group.id, userId: userId)
            await chat.loadMuteState(groupId: group.id, userId: userId)
            await chat.markRead(groupId: group.id, userId: userId)
        }
        .onDisappear {
            guard let userId = appState.currentUserId else { return }
            let groupId = group.id
            Task { await appState.chatService.markRead(groupId: groupId, userId: userId) }
            appState.chatService.stopObserving()
        }
    }

    // MARK: - Feed

    private var chatContent: some View {
        VStack(spacing: 0) {
            if !didAcknowledgeGuidelines {
                guidelinesNotice
            }

            if let error = chat.errorMessage {
                ContextualTipBanner(icon: "exclamationmark.triangle.fill", message: error)
                    .padding(.bottom, 8)
            }

            messageList
            composer
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.hasMoreHistory {
                        loadEarlierButton
                    }

                    ForEach(messages) { message in
                        ChatMessageRow(
                            message: message,
                            isOwn: message.userId == appState.currentUserId,
                            onModerate: { moderationTarget = message }
                        )
                        .id(message.id)
                    }

                    // Scroll anchor: keeps the newest message above the composer.
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorId)
                }
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if messages.isEmpty {
                    ContentUnavailableView(
                        "No Messages Yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start the smack talk — everyone in \(group.name) will see it.")
                    )
                }
            }
            .onChange(of: messages.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
            }
        }
    }

    private var bottomAnchorId: String { "chat.bottom" }

    private var loadEarlierButton: some View {
        Button {
            Task { await chat.loadOlderMessages() }
        } label: {
            HStack(spacing: 6) {
                if chat.isLoadingOlder {
                    ProgressView().tint(theme.accent)
                }
                Text(chat.isLoadingOlder ? "Loading…" : "Load earlier messages")
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.accent)
        .disabled(chat.isLoadingOlder)
        .padding(.bottom, 4)
    }

    // MARK: - Guidelines (first run)

    private var guidelinesNotice: some View {
        PickemsCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("House rules", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text("Be cool. Reported messages are reviewed and accounts can be removed. Long press any message to report it, block its author, or delete your own.")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Got it") {
                        didAcknowledgeGuidelines = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)

                    if let url = AppConfig.termsOfServiceURL {
                        Link("Terms", destination: url)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 4) {
            if trimmedDraft.count > ChatMessage.maxTextLength - 100 {
                Text("\(trimmedDraft.count)/\(ChatMessage.maxTextLength)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        trimmedDraft.count > ChatMessage.maxTextLength
                            ? PickemsColors.warning
                            : PickemsColors.textSecondary
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(PickemsColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("Message")

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(theme.onAccent)
                        .frame(width: 34, height: 34)
                        .background(canSend ? theme.accent : PickemsColors.cardBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(PickemsColors.background.opacity(0.9))
    }

    private func send() {
        guard canSend, let author = appState.authService.currentUser else { return }
        let text = trimmedDraft
        draft = ""
        PickemsHaptics.lightImpact()
        Task {
            await appState.chatService.send(
                text: text,
                groupId: group.id,
                weekId: appState.groupService.currentWeek?.id,
                author: author
            )
        }
    }

    // MARK: - Menu

    private var chatMenu: some View {
        Menu {
            Button {
                guard let userId = appState.currentUserId else { return }
                let muted = !chat.isMuted
                Task {
                    await appState.chatService.setMuted(muted, groupId: group.id, userId: userId)
                }
            } label: {
                Label(
                    chat.isMuted ? "Unmute notifications" : "Mute notifications",
                    systemImage: chat.isMuted ? "bell" : "bell.slash"
                )
            }

            Button {
                showBlockedUsers = true
            } label: {
                Label("Blocked people", systemImage: "hand.raised")
            }

            Button {
                didAcknowledgeGuidelines = false
            } label: {
                Label("House rules", systemImage: "info.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Chat options")
        }
    }
}

/// Lets a member undo a block — Guideline 1.2 expects blocking to be reversible.
private struct ChatBlockedUsersSheet: View {
    let group: PickemGroup

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let blocked = appState.chatService.blockedUserIds.sorted()
                if blocked.isEmpty {
                    Text("You haven't blocked anyone.")
                        .font(.subheadline)
                        .foregroundStyle(PickemsColors.textSecondary)
                } else {
                    ForEach(blocked, id: \.self) { userId in
                        HStack {
                            Text(displayName(for: userId))
                                .font(.subheadline)
                            Spacer()
                            Button("Unblock") {
                                guard let ownerId = appState.currentUserId else { return }
                                appState.chatService.unblock(userId: userId, ownerId: ownerId)
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .navigationTitle("Blocked People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func displayName(for userId: String) -> String {
        appState.groupService.members.first { $0.id == userId }?.displayName
            ?? appState.chatService.visibleMessages.first { $0.userId == userId }?.displayName
            ?? "Blocked member"
    }
}
