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
                                        .foregroundStyle(PickemsColors.accent)
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
    var size: Font = .body

    @State private var showHelp = false

    var body: some View {
        Button {
            PickemsHaptics.lightImpact()
            showHelp = true
        } label: {
            Image(systemName: "info.circle")
                .font(size)
                .foregroundStyle(PickemsColors.textSecondary)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Help")
        .accessibilityHint(topic.title)
        .sheet(isPresented: $showHelp) {
            HelpDetailView(topic: topic)
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
        .accessibilityElement(children: .combine)
    }
}

struct ContextualTipBanner: View {
    let icon: String
    let message: String
    var help: HelpTopic? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(PickemsColors.accent)
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
                .strokeBorder(PickemsColors.accent.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

struct HelpToolbarButton: View {
    let topic: HelpTopic

    var body: some View {
        HelpInfoButton(topic: topic, size: .body)
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
