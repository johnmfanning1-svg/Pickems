import SwiftUI

/// One modal per container. Nested inside `pickemsEnvironment` so a sheet
/// opened from a row (help, invite, share) does not attach to that row.
enum ScreenModal: Identifiable {
    case help(HelpTopic)
    case shareResults(ShareSource, XAuthService, id: UUID)
    case shareApp(leagueName: String?, XAuthService, id: UUID)
    case activity(items: [Any], id: UUID)
    case shareSheet(items: [Any], id: UUID)
    case messageCompose(body: String, id: UUID)

    var id: String {
        switch self {
        case .help(let topic):
            return topic.id
        case .shareResults(_, _, let id),
             .shareApp(_, _, let id),
             .activity(_, let id),
             .shareSheet(_, let id),
             .messageCompose(_, let id):
            return id.uuidString
        }
    }
}

@MainActor
@Observable
final class HelpPresenter {
    var modal: ScreenModal?

    /// Existing callers (`HelpInfoButton`) set a topic. That is the help case.
    var topic: HelpTopic? {
        get {
            if case .help(let topic) = modal {
                return topic
            }
            return nil
        }
        set {
            if let newValue {
                modal = .help(newValue)
            } else if case .help = modal {
                modal = nil
            }
        }
    }
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
            .sheet(item: $presenter.modal) { (modal: ScreenModal) in
                screenModalContent(modal)
            }
    }

    @ViewBuilder
    private func screenModalContent(_ modal: ScreenModal) -> some View {
        switch modal {
        case .help(let topic):
            helpSheet(topic)
        case .shareResults(let source, let xAuth, _):
            shareResultsSheet(source, xAuth: xAuth)
        case .shareApp(let leagueName, let xAuth, _):
            shareAppSheet(leagueName: leagueName, xAuth: xAuth)
        case .activity(let items, _):
            ActivityView(items: items)
        case .shareSheet(let items, _):
            inviteShareSheet(items)
        case .messageCompose(let body, _):
            MessageComposeView(body: body)
        }
    }

    private func helpSheet(_ topic: HelpTopic) -> some View {
        HelpDetailView(topic: topic)
            .environment(\.themePalette, theme)
            .pickemsSheetChrome()
    }

    private func shareResultsSheet(_ source: ShareSource, xAuth: XAuthService) -> some View {
        ShareResultsSheet(source: source)
            .environmentObject(xAuth)
            .environment(\.themePalette, theme)
    }

    private func shareAppSheet(leagueName: String?, xAuth: XAuthService) -> some View {
        ShareAppSheet(leagueName: leagueName)
            .environmentObject(xAuth)
    }

    private func inviteShareSheet(_ items: [Any]) -> some View {
        ShareSheet(items: items)
            .presentationDetents([.medium, .large])
    }
}

extension View {
    func presentsHelp() -> some View {
        modifier(PresentsHelpModifier())
    }
}
