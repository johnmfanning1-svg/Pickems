import SwiftUI

/// One chat bubble. Own messages sit right in the accent colour; everyone else
/// gets an avatar, a name, and a card bubble on the left.
struct ChatMessageRow: View {
    @Environment(\.themePalette) private var theme

    let message: ChatMessage
    let isOwn: Bool
    /// Opens `ChatModerationSheet` — report / block / delete-own.
    let onModerate: () -> Void

    var body: some View {
        if message.isDeleted {
            deletedPlaceholder
        } else {
            bubble
        }
    }

    // MARK: - Deleted

    private var deletedPlaceholder: some View {
        Text("Message deleted")
            .font(.caption.italic())
            .foregroundStyle(PickemsColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
            .padding(.horizontal)
            .accessibilityLabel("Message deleted")
    }

    // MARK: - Bubble

    private var bubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 44)
            } else {
                InitialsAvatar(
                    initials: message.initials,
                    colorHex: message.avatarColorHex,
                    size: 28
                )
                .accessibilityHidden(true)
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if !isOwn {
                    Text(message.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(isOwn ? theme.onAccent : PickemsColors.textPrimary)
                    .multilineTextAlignment(isOwn ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isOwn ? theme.accent : PickemsColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(timestampLabel)
                    .font(.caption2)
                    .foregroundStyle(PickemsColors.textSecondary)
            }

            if !isOwn {
                Spacer(minLength: 44)
            }
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button(role: isOwn ? ButtonRole.destructive : nil) {
                onModerate()
            } label: {
                Label(
                    isOwn ? "Delete Message" : "Report or Block",
                    systemImage: isOwn ? "trash" : "flag"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isOwn ? "Long press to delete" : "Long press to report or block")
    }

    // MARK: - Copy

    private var timestampLabel: String {
        guard let createdAt = message.createdAt else { return "Sending…" }
        return createdAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    private var accessibilityLabel: String {
        let who = isOwn ? "You" : message.displayName
        return "\(who) said \(message.text), \(timestampLabel)"
    }
}
