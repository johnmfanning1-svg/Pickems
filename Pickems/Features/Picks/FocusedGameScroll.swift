import SwiftUI

/// Scrolls the Pickems list to the game a notification opened.
struct FocusedGameScrollModifier: ViewModifier {
    let gameId: String?
    let gamesSignature: String

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onAppear { scroll(gameId, proxy: proxy) }
                .onChange(of: gameId) { _, id in
                    scroll(id, proxy: proxy)
                }
                .onChange(of: gamesSignature) { _, _ in
                    scroll(gameId, proxy: proxy)
                }
        }
    }

    private func scroll(_ gameId: String?, proxy: ScrollViewProxy) {
        guard let gameId else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(focusedGameRowId(gameId), anchor: .center)
            }
        }
    }
}

func focusedGameRowId(_ gameId: String) -> String {
    "game-\(gameId)"
}
