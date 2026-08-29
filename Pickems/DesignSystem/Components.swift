import SwiftUI

struct PickemsTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding()
            .background(PickemsColors.cardBackground)
            .foregroundStyle(PickemsColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension TextFieldStyle where Self == PickemsTextFieldStyle {
    static var pickems: PickemsTextFieldStyle { PickemsTextFieldStyle() }
}

struct InitialsAvatar: View {
    let initials: String
    let colorHex: String
    var imageURL: String? = nil
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(PickemsColors.color(from: colorHex))
            Text(initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct PickemsSearchField: View {
    @Binding var text: String
    var prompt: String = "Search"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PickemsColors.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(PickemsColors.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(PickemsColors.cardBackground)
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
    }
}

struct SeasonWeekHeader: View {
    let label: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(PickemsColors.cardBackground)
    }
}

struct PrimaryButton: View {
    @Environment(\.themePalette) private var theme
    let title: String
    var isLoading: Bool = false
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            PickemsHaptics.lightImpact()
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(theme.onAccent)
                }
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(theme.accent)
            .foregroundStyle(theme.onAccent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isLoading)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

struct SecondaryButton: View {
    @Environment(\.themePalette) private var theme
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button {
            PickemsHaptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(PickemsColors.cardBackground)
            .foregroundStyle(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PickemsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .background(PickemsColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(text)")
    }
}

struct CountStatusMeter: View {
    let made: Int
    let total: Int
    let status: SubmissionRosterStatus
    var unitName: String = "Pickems"

    var body: some View {
        HStack(spacing: 6) {
            Text(countText)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
            Image(systemName: status.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var countText: String {
        total > 0 ? "\(made)/\(total)" : "\(made)"
    }

    private var tint: Color {
        switch status {
        case .submitted: return PickemsColors.success
        case .inProgress: return PickemsColors.covering
        case .notStarted: return PickemsColors.textSecondary
        }
    }

    private var accessibilityText: String {
        if total > 0 {
            return "\(made) of \(total) \(unitName), \(status.label)"
        }
        return status.label
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var help: HelpTopic? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(PickemsColors.textSecondary)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(PickemsColors.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let help {
                HelpInfoButton(topic: help, size: .title3)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Shown while a tab's pull-to-refresh is waiting on a server round-trip.
struct RefreshingBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(PickemsColors.textPrimary)
            Text("Refreshing…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(PickemsColors.cardBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Refreshing")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Pull-to-refresh that keeps a visible pending banner until `action` finishes.
    func pickemsRefreshable(
        isRefreshing: Binding<Bool>,
        action: @escaping () async -> Void
    ) -> some View {
        safeAreaInset(edge: .top) {
            if isRefreshing.wrappedValue {
                RefreshingBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isRefreshing.wrappedValue)
        .refreshable {
            isRefreshing.wrappedValue = true
            await action()
            isRefreshing.wrappedValue = false
        }
    }
}

