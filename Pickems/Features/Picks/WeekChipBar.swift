import SwiftUI

/// Horizontal week chips used on Selections, Pickems, Week Recap, and Commissioner Settings.
struct WeekChipBar: View {
    @Environment(\.themePalette) private var theme
    let weeks: [WeekSummary]
    let selectedWeekId: String?
    let activeWeekId: String?
    let dateRangeLabel: (WeekSummary) -> String?
    var accessibilityHint: String = "View this week"
    var showsCaption: Bool = true
    var horizontalPadding: CGFloat = 16
    /// When false, a commissioner/Picks load finishing must not yank the scroll position after a tap.
    var scrollWhenWeekListChanges: Bool = true
    let onSelect: (WeekSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsCaption {
                Text("Week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PickemsColors.textSecondary)
                    .padding(.horizontal, horizontalPadding)
                    .accessibilityAddTraits(.isHeader)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(weeks) { week in
                            weekTab(week)
                                .id(week.id)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                }
                .onAppear { scrollToSelected(proxy) }
                .onChange(of: selectedWeekId) { _, newId in
                    guard newId != nil else { return }
                    scrollToSelected(proxy)
                }
                .onChange(of: weeks.map(\.id)) { _, _ in
                    guard scrollWhenWeekListChanges else { return }
                    scrollToSelected(proxy)
                }
            }
        }
    }

    private func weekTab(_ week: WeekSummary) -> some View {
        let isSelected = week.id == selectedWeekId
        let isActive = week.id == activeWeekId
        let range = dateRangeLabel(week) ?? ""
        return Button {
            onSelect(week)
        } label: {
            VStack(spacing: 2) {
                Text(CFBBowlSeason.chipPrimaryLabel(for: week))
                    .font(.subheadline.weight(.semibold))
                Text(range.isEmpty ? " " : range)
                    .font(.caption2.weight(.medium))
                    .opacity(range.isEmpty ? 0 : (isSelected ? 0.9 : 0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? theme.accent : PickemsColors.cardBackground)
            .foregroundStyle(isSelected ? theme.onAccent : PickemsColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isActive {
                    Circle()
                        .fill(isSelected ? theme.onAccent.opacity(0.92) : theme.accent)
                        .frame(width: 7, height: 7)
                        .offset(x: -5, y: 5)
                        .accessibilityHidden(true)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        chipStrokeColor(isSelected: isSelected, isActive: isActive),
                        lineWidth: chipStrokeWidth(isSelected: isSelected, isActive: isActive)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: week, isActive: isActive))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isActive ? "Current week" : accessibilityHint)
    }

    private func chipStrokeColor(isSelected: Bool, isActive: Bool) -> Color {
        if isSelected { return .clear }
        if isActive { return theme.accent.opacity(0.42) }
        return PickemsColors.hairline
    }

    private func chipStrokeWidth(isSelected: Bool, isActive: Bool) -> CGFloat {
        isActive && !isSelected ? 1.25 : 1
    }

    private func accessibilityLabel(for week: WeekSummary, isActive: Bool) -> String {
        var label = "Week \(week.weekNumber)"
        if let range = dateRangeLabel(week), !range.isEmpty {
            label += ", \(range)"
        }
        if isActive {
            label += ", current"
        }
        return label
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy) {
        guard let selectedWeekId else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(selectedWeekId, anchor: .center)
            }
        }
    }
}
