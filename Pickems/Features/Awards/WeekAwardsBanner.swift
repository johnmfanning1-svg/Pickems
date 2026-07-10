import SwiftUI

struct WeekAwardsBanner: View {
    @Environment(\.themePalette) private var theme
    let awards: WeekAwards
    @Environment(AppState.self) private var appState

    private func name(for userId: String?) -> String {
        guard let userId else { return "—" }
        return appState.groupService.members.first(where: { $0.id == userId })?.displayName ?? "Player"
    }

    var body: some View {
        PickemsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Week Awards")
                    .font(PickemsTypography.section)
                    .foregroundStyle(PickemsColors.textPrimary)

                awardRow(title: "Sharpshooter", subtitle: "Best W–L", name: name(for: awards.sharpshooterUserId), icon: "scope")
                awardRow(title: "Heartbreaker", subtitle: "Most near-misses", name: name(for: awards.heartbreakerUserId), icon: "heart.slash")
                awardRow(title: "Contrarian", subtitle: "Most unique covers", name: name(for: awards.contrarianUserId), icon: "arrow.triangle.branch")
            }
        }
    }

    private func awardRow(title: String, subtitle: String, name: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
            Spacer()
            Text(name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(theme.accent)
        }
    }
}

struct StreakBadgeView: View {
    @Environment(\.themePalette) private var theme
    let streak: Int
    var isPerfect: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let label = StreakEngine.badgeLabel(for: streak) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.accent.opacity(0.2))
                    .foregroundStyle(theme.accent)
                    .clipShape(Capsule())
            }
            if isPerfect {
                Text("Perfect Saturday")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PickemsColors.success.opacity(0.2))
                    .foregroundStyle(PickemsColors.success)
                    .clipShape(Capsule())
            }
        }
    }
}
