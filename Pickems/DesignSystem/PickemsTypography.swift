import SwiftUI

enum PickemsTypography {
    /// Expressive display face for ranks, Cover Moments, and dynasty crowns.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let rank = Font.system(size: 28, weight: .bold, design: .rounded)
    static let section = Font.system(size: 20, weight: .semibold, design: .default)
}

struct RankChangeMotion: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content
            .scaleEffect(1)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: trigger)
    }
}

struct PulseAccentModifier: ViewModifier {
    @State private var pulse = false
    var enabled: Bool = true

    func body(content: Content) -> some View {
        content
            .opacity(enabled && pulse ? 0.85 : 1)
            .onAppear {
                guard enabled else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

extension View {
    func pickemsRankMotion(trigger: Int) -> some View {
        modifier(RankChangeMotion(trigger: trigger))
    }

    func pickemsPulse(enabled: Bool = true) -> some View {
        modifier(PulseAccentModifier(enabled: enabled))
    }

    func pickemsAppear() -> some View {
        modifier(AppearSlideModifier())
    }
}

private struct AppearSlideModifier: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
            .onAppear {
                // Only animate the first time this view identity appears.
                // Re-running on every parent refresh caused Home to "twitch".
                guard !shown else { return }
                withAnimation(.easeOut(duration: 0.35)) { shown = true }
            }
    }
}
