import SwiftUI

struct SmackTalkQuickRepliesBar: View {
    let replies: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(replies, id: \.self) { reply in
                    Button {
                        onSelect(reply)
                    } label: {
                        Text(reply)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

#if DEBUG
struct SmackTalkQuickRepliesBar_Previews: PreviewProvider {
    static var previews: some View {
        SmackTalkQuickRepliesBar(
            replies: SmackTalkTextBuilder.quickReplies(for: DemoData.weeklyResult),
            onSelect: { _ in }
        )
    }
}
#endif
