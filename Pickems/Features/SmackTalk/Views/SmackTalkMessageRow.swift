import SwiftUI

struct SmackTalkMessageRow: View {
    let message: SmackTalkMessage
    let isCurrentUser: Bool

    var body: some View {
        switch message.kind {
        case .system:
            systemRow
        case .user:
            userRow
        }
    }

    private var systemRow: some View {
        Text(message.text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private var userRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isCurrentUser {
                Spacer(minLength: 48)
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser {
                    Text(message.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .font(.body)
                    .foregroundStyle(isCurrentUser ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if !isCurrentUser {
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal)
    }

    private var bubbleColor: Color {
        isCurrentUser ? Color.accentColor : Color(.secondarySystemBackground)
    }
}

#if DEBUG
struct SmackTalkMessageRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            SmackTalkMessageRow(
                message: SmackTalkMessage(
                    id: "1",
                    threadId: "demo",
                    userId: "user-2",
                    displayName: "Drew",
                    text: "Georgia -3.5 was free money.",
                    createdAt: Date(),
                    kind: .user
                ),
                isCurrentUser: false
            )
            SmackTalkMessageRow(
                message: SmackTalkMessage(
                    id: "2",
                    threadId: "demo",
                    userId: "user-1",
                    displayName: "JMF",
                    text: "See you at the bottom of the standings.",
                    createdAt: Date(),
                    kind: .user
                ),
                isCurrentUser: true
            )
        }
        .padding()
    }
}
#endif
