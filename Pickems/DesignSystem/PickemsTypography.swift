import SwiftUI

enum PickemsTypography {
    /// Expressive display face for ranks, Cover Moments, and dynasty crowns.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let rank = Font.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()
    static let section = Font.system(size: 20, weight: .semibold, design: .default)
}

/// One-shot rank pop when the number improves (a lower rank). Reduce Motion keeps a crossfade.
struct RankChangeMotion: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = 0
    @State private var ready = false

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(trigger)))
            .phaseAnimator([CGFloat(1.0), 1.12, 1.0], trigger: pulse) { view, phase in
                view.scaleEffect(reduceMotion ? 1 : phase)
            } animation: { _ in
                .spring(response: 0.45, dampingFraction: 0.7)
            }
            .onChange(of: trigger) { old, new in
                guard ready, new < old, !reduceMotion else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    pulse += 1
                }
            }
            .onAppear { ready = true }
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.45, dampingFraction: 0.7),
                value: trigger
            )
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
