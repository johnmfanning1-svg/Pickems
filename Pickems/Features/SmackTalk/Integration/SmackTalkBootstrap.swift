import SwiftUI

/// Attach to your app root to enable week-to-week league smack talk.
struct SmackTalkBootstrap<Content: View>: View {
    @StateObject private var smackTalkService = LocalSmackTalkService()

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(smackTalkService)
    }
}

extension View {
    func withSmackTalkSupport(_ service: LocalSmackTalkService) -> some View {
        environmentObject(service)
    }
}
