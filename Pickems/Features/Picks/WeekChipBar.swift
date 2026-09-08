import SwiftUI

/// Horizontal week chips used on Selections, Pickems, and Week Recap.
struct WeekChipBar: View {
    @Environment(\.themePalette) private var theme
    let weeks: [WeekSummary]
    let selectedWeekId: String?
    let activeWeekId: String?
    let dateRangeLabel: (WeekSummary) -> String?
    var accessibilityHint: String = "View this week"
    let onSelect: (WeekSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(weeks) { week in
                            weekTab(week)
                                .id(week.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onAppear { scrollToSelected(proxy) }
                .onChange(of: selectedWeekId) { _, _ in scrollToSelected(proxy) }
                .onChange(of: weeks.map(\.id)) { _, _ in scrollToSelected(proxy) }
            }
        }
    }

    private func weekTab(_ week: WeekSummary) -> some View {
        let isSelected = week.id == selectedWeekId
        let isActive = week.id == activeWeekId
        return Button {
            onSelect(week)
        } label: {
            VStack(spacing: 2) {
                Text("Week \(week.weekNumber)")
                    .font(.subheadline.weight(.semibold))
                if let range = dateRangeLabel(week), !range.isEmpty {
                    Text(range)
                        .font(.caption2.weight(.medium))
                        .opacity(isSelected ? 0.9 : 0.7)
                }
                if isActive {
                    Text("Current")
                        .font(.caption2.weight(.medium))
                        .opacity(isSelected ? 0.9 : 0.7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? theme.accent : PickemsColors.cardBackground)
            .foregroundStyle(isSelected ? theme.onAccent : PickemsColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: week))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isActive ? "Current week" : accessibilityHint)
    }

    private func accessibilityLabel(for week: WeekSummary) -> String {
        if let range = dateRangeLabel(week), !range.isEmpty {
            return "Week \(week.weekNumber), \(range)"
        }
        return "Week \(week.weekNumber)"
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
