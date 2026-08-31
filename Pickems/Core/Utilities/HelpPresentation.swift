import SwiftUI

/// One help sheet per container. Nested inside `pickemsEnvironment` so help
/// opened from a sheet (Join, Settings) does not replace that sheet at the root.
@MainActor
@Observable
final class HelpPresenter {
    var topic: HelpTopic?
}

private struct HelpPresenterKey: EnvironmentKey {
    static let defaultValue: HelpPresenter? = nil
}

extension EnvironmentValues {
    var helpPresenter: HelpPresenter? {
        get { self[HelpPresenterKey.self] }
        set { self[HelpPresenterKey.self] = newValue }
    }
}

struct PresentsHelpModifier: ViewModifier {
    @State private var presenter = HelpPresenter()
    @Environment(\.themePalette) private var theme

    func body(content: Content) -> some View {
        @Bindable var presenter = presenter
        content
            .environment(\.helpPresenter, presenter)
            .sheet(item: $presenter.topic) { topic in
                HelpDetailView(topic: topic)
                    .environment(\.themePalette, theme)
                    .pickemsSheetChrome()
            }
    }
}

extension View {
    func presentsHelp() -> some View {
        modifier(PresentsHelpModifier())
    }
}
