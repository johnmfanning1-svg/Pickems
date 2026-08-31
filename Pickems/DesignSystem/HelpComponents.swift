import SwiftUI

// MARK: - Haptics

enum PickemsHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Help UI

struct HelpDetailView: View {
    let topic: HelpTopic
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(topic.message)
                        .font(.body)
                        .foregroundStyle(PickemsColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !topic.tips.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tips")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PickemsColors.textSecondary)

                            ForEach(topic.tips, id: \.self) { tip in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(theme.accent)
                                        .padding(.top, 2)
                                        .accessibilityHidden(true)
                                    Text(tip)
                                        .font(.subheadline)
                                        .foregroundStyle(PickemsColors.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PickemsColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding()
            }
            .background(PickemsColors.background)
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct HelpInfoButton: View {
    let topic: HelpTopic
    var size: Font = .callout
    /// Optical glyph frame for inline/section use. Toolbar uses `.center`.
    var alignment: Alignment = .trailing
    /// When set, parent presents help (required inside `Form` section headers — nested sheets/taps fail there).
    var presentedTopic: Binding<HelpTopic?>? = nil
    /// Nav-bar usage: skip the 30pt frame and use a compact control so Liquid Glass
    /// does not inflate the capsule around the glyph.
    var isToolbar: Bool = false
    @Environment(\.themePalette) private var theme

    @Environment(\.helpPresenter) private var helpPresenter
    @State private var showHelp = false

    var body: some View {
        if helpPresenter == nil, presentedTopic == nil {
            helpButton
                .sheet(isPresented: $showHelp) {
                    HelpDetailView(topic: topic)
                        .environment(\.themePalette, theme)
                        .pickemsSheetChrome()
                }
        } else {
            helpButton
        }
    }

    private var helpButton: some View {
        Button {
            PickemsHaptics.lightImpact()
            PickemsPresentation.afterTap {
                if let presentedTopic {
                    presentedTopic.wrappedValue = topic
                } else if let helpPresenter {
                    helpPresenter.topic = topic
                } else {
                    showHelp = true
                }
            }
        } label: {
            glyph
        }
        .buttonStyle(.borderless)
        .controlSize(isToolbar ? .mini : .regular)
        .accessibilityLabel("Help")
        .accessibilityHint(topic.title)
    }

    @ViewBuilder
    private var glyph: some View {
        let icon = Image(systemName: "info.circle")
            .font(isToolbar ? .subheadline : size)
            .imageScale(isToolbar ? .small : .medium)
            .foregroundStyle(PickemsColors.textSecondary)
            .symbolRenderingMode(.hierarchical)

        if isToolbar {
            icon
        } else {
            icon
                .frame(width: 30, height: 30, alignment: alignment)
                // Expand hit testing without growing the visible toolbar footprint.
                .contentShape(Rectangle().inset(by: -7))
        }
    }
}

struct PickemsSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var help: HelpTopic? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let help {
                HelpInfoButton(topic: help, size: .subheadline)
            }
        }
        .padding(.horizontal)
        // Keep children separate so the help button remains tappable/accessible.
        .accessibilityElement(children: .contain)
    }
}

struct ContextualTipBanner: View {
    let icon: String
    let message: String
    var help: HelpTopic? = nil
    @Environment(\.themePalette) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let help {
                HelpInfoButton(topic: help, size: .subheadline)
            }
        }
        .padding()
        .background(PickemsColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

struct HelpToolbarButton: View {
    let topic: HelpTopic

    var body: some View {
        HelpInfoButton(topic: topic, alignment: .center, isToolbar: true)
    }
}

/// Trailing nav-bar help control. Hides the shared Liquid Glass background so the
/// compact “i” is not wrapped in an oversized capsule.
struct HelpToolbarItem: ToolbarContent {
    let topic: HelpTopic

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HelpToolbarButton(topic: topic)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

extension View {
    func pickemsListRowBackground() -> some View {
        self.listRowBackground(PickemsColors.cardBackground)
    }

    func pickemsScreenBackground() -> some View {
        modifier(PickemsScreenBackgroundModifier())
    }
}

private struct PickemsScreenBackgroundModifier: ViewModifier {
    @Environment(\.themePalette) private var theme

    func body(content: Content) -> some View {
        content.background {
            PickemsAtmosphericBackground(palette: theme)
        }
    }
}
