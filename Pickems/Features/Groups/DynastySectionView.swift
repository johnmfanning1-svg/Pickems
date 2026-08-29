import SwiftUI

struct DynastySectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    private var archives: [SeasonArchive] {
        appState.groupService.seasonArchives
    }

    private var subtitle: String {
        if let latest = archives.first {
            let year = latest.seasonYear.pickemsYearString
            if let name = latest.championDisplayName, !name.isEmpty {
                return "\(year) Champion · \(name)"
            }
            return "\(year) season archived"
        }
        return "Champions and career records"
    }

    var body: some View {
        NavigationLink {
            DynastyDetailView()
        } label: {
            PickemsCard {
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.title3)
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dynasty")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accent)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dynasty")
        .accessibilityHint("View champions and career records")
        .accessibilityValue(subtitle)
    }
}

struct DynastyDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    private var archives: [SeasonArchive] {
        appState.groupService.seasonArchives
    }

    private var careers: [CareerRecord] {
        appState.groupService.careerRecords.sorted {
            if $0.titles != $1.titles { return $0.titles > $1.titles }
            return $0.seasonWins > $1.seasonWins
        }
    }

    var body: some View {
        List {
            Section {
                if archives.isEmpty {
                    Text("No archived seasons yet.")
                        .foregroundStyle(PickemsColors.textSecondary)
                        .listRowBackground(PickemsColors.cardBackground)
                } else {
                    ForEach(archives) { archive in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(archive.seasonYear.pickemsYearString)
                                    .font(.headline)
                                    .foregroundStyle(PickemsColors.textPrimary)
                                Spacer()
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(theme.accent)
                                Text(archive.championDisplayName ?? "—")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.accent)
                            }
                            if let champ = archive.finalStandings.first {
                                Text("Final: \(champ.seasonWins)-\(champ.seasonLosses) · \(archive.weekCount) weeks played")
                                    .font(.caption)
                                    .foregroundStyle(PickemsColors.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                }
            } header: {
                Text("Champions")
            }

            Section {
                if careers.isEmpty {
                    Text("Career records appear after the first season close.")
                        .foregroundStyle(PickemsColors.textSecondary)
                        .listRowBackground(PickemsColors.cardBackground)
                } else {
                    ForEach(careers) { career in
                        HStack {
                            InitialsAvatar(
                                initials: String(career.displayName.prefix(2)).uppercased(),
                                colorHex: career.avatarColorHex,
                                size: 40
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(career.displayName)
                                    .font(.headline)
                                    .foregroundStyle(PickemsColors.textPrimary)
                                Text("\(career.titles) titles · \(career.seasonsPlayed) seasons")
                                    .font(.caption)
                                    .foregroundStyle(PickemsColors.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(career.recordLabel)
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(PickemsColors.textPrimary)
                                if let best = career.bestFinish {
                                    Text("Best #\(best)")
                                        .font(.caption2)
                                        .foregroundStyle(PickemsColors.textSecondary)
                                }
                            }
                        }
                        .listRowBackground(PickemsColors.cardBackground)
                    }
                }
            } header: {
                Text("Career")
            }
        }
        .scrollContentBackground(.hidden)
        .pickemsScreenBackground()
        .navigationTitle("Dynasty Wall")
        .navigationBarTitleDisplayMode(.inline)
    }
}