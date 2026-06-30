import SwiftUI

struct WeekSmackTalkView: View {
    @EnvironmentObject private var smackTalkService: LocalSmackTalkService

    let context: SmackTalkContext
    let weeklyResult: WeeklyResult?

    @State private var messages: [SmackTalkMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isComposerFocused: Bool

    init(context: SmackTalkContext, weeklyResult: WeeklyResult? = nil) {
        self.context = context
        self.weeklyResult = weeklyResult
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            quickReplies
            composer
        }
        .navigationTitle(context.thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(context.thread.title)
                        .font(.headline)
                    Text(context.thread.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            smackTalkService.seedDemoMessagesIfNeeded(for: context.thread)
            smackTalkService.observeMessages(for: context.thread) { updated in
                messages = updated
            }
        }
        .onDisappear {
            smackTalkService.stopObserving(for: context.thread)
        }
        .alert("Couldn't Send", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        ContentUnavailableView(
                            "No smack talk yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Be the first to talk trash this week.")
                        )
                        .padding(.top, 48)
                    } else {
                        ForEach(messages) { message in
                            SmackTalkMessageRow(
                                message: message,
                                isCurrentUser: message.userId == context.userId && message.kind == .user
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private var quickReplies: some View {
        if let weeklyResult {
            SmackTalkQuickRepliesBar(
                replies: SmackTalkTextBuilder.quickReplies(for: weeklyResult),
                onSelect: { draft = $0 }
            )
            .background(Color(.systemBackground))
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Talk your picks...", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .focused($isComposerFocused)

                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                }
                .disabled(trimmedDraft.isEmpty || isSending)
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private func sendMessage() async {
        isSending = true
        defer { isSending = false }

        do {
            try await smackTalkService.sendMessage(text: draft, context: context)
            draft = ""
            isComposerFocused = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
struct WeekSmackTalkView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            WeekSmackTalkView(
                context: SmackTalkDemoData.currentContext,
                weeklyResult: DemoData.weeklyResult
            )
        }
        .environmentObject(LocalSmackTalkService())
    }
}
#endif
