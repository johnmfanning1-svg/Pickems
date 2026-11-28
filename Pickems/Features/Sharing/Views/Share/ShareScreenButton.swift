import SwiftUI

struct ShareScreenButton: View {
    enum Style {
        case toolbarIcon
        case headerAccessory
    }

    let accessibilityLabel: String
    var isEnabled: Bool = true
    var style: Style = .toolbarIcon
    let buildContent: () -> ScreenShareContent?

    @Environment(\.helpPresenter) private var helpPresenter
    @Environment(\.themePalette) private var theme
    @State private var isRendering = false
    @State private var showFallbackSheet = false
    @State private var shareItems: [Any] = []

    var body: some View {
        if isEnabled {
            button
                .sheet(isPresented: $showFallbackSheet) { // presentation-ok: fallback when no screen presenter
                    ActivityView(items: shareItems)
                }
        }
    }

    @ViewBuilder
    private var button: some View {
        switch style {
        case .toolbarIcon:
            toolbarButton
        case .headerAccessory:
            headerButton
        }
    }

    private var toolbarButton: some View {
        Button(action: presentShare) {
            Group {
                if isRendering {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(isRendering)
        .accessibilityLabel(accessibilityLabel)
    }

    private var headerButton: some View {
        Button(action: presentShare) {
            Group {
                if isRendering {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isRendering)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(accessibilityLabel)
    }

    private func presentShare() {
        guard !isRendering else { return }
        PickemsHaptics.lightImpact()
        isRendering = true

        Task { @MainActor in
            defer { isRendering = false }
            guard let content = buildContent(),
                  let image = ShareCardRenderer.renderScreenCard(content) else {
                return
            }
            let caption = content.caption
            let title = content.contextLabel
            let payload = ScreenSharePayload(title: title, caption: caption, image: image)
            let items: [Any] = [payload]
            let modal = ScreenModal.activity(items: items, id: UUID())
            PickemsPresentation.afterTap {
                if let helpPresenter {
                    helpPresenter.modal = modal
                } else {
                    shareItems = items
                    showFallbackSheet = true
                }
            }
        }
    }
}