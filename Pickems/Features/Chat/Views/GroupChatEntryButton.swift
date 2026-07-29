import SwiftUI

/// Contract C4 — the Groups-tab entry point into chat. Self-contained: label,
/// unread badge, `NavigationLink`, and the `appConfig/live.chatEnabled` check,
/// so Lane D can drop it into the actions grid without any wiring.
struct GroupChatEntryButton: View {
    let group: PickemGroup

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var unreadCount = 0

    var body: some View {
        if appState.chatService.chatEnabled {
            NavigationLink {
                GroupChatView(group: group)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Open group chat")
            .task(id: group.id) {
                await refreshBadge()
            }
        }
    }

    private var label: some View {
        Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(PickemsColors.cardBackground)
            .foregroundStyle(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if unreadCount > 0 {
                    Text(badgeText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accent)
                        .clipShape(Capsule())
                        .offset(x: -6, y: -6)
                        .accessibilityHidden(true)
                }
            }
    }

    private var badgeText: String {
        unreadCount > ChatService.unreadBadgeCap ? "\(ChatService.unreadBadgeCap)+" : "\(unreadCount)"
    }

    private var accessibilityLabel: String {
        unreadCount > 0 ? "Chat, \(unreadCount) unread" : "Chat"
    }

    private func refreshBadge() async {
        guard let userId = appState.currentUserId else { return }
        await appState.chatService.refreshRemoteConfig()
        appState.chatService.loadLocalModerationState(userId: userId)
        unreadCount = await appState.chatService.unreadCount(groupId: group.id, userId: userId)
    }
}
