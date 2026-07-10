import SwiftUI

struct DynastySectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme

    private var archives: [SeasonArchive] {
        appState.groupService.seasonArchives
    }

    private var topCareers: [CareerRecord] {
        appState.groupService.careerRecords.sorted {
            if $0.titles != $1.titles { return $0.titles > $1.titles }
            if $0.seasonWins != $1.seasonWins { return $0.seasonWins > $1.seasonWins }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dynasty")
                    .font(.headline)
                    .foregroundStyle(PickemsColors.textPrimary)
                Spacer()
                NavigationLink {
                    DynastyDetailView()
                } label: {
                    Text("See All")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }
            }

            if archives.isEmpty && topCareers.isEmpty {
                PickemsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No crowns yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PickemsColors.textPrimary)
                        Text("When the commissioner closes a season, champions and career records live here.")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if let latest = archives.first {
                    championBanner(latest)
                }

                if !topCareers.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(topCareers.prefix(3)) { career in
                            careerRow(career)
                        }
                    }
                }
            }
        }
    }

    private func championBanner(_ archive: SeasonArchive) -> some View {
        PickemsCard {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(archive.seasonYear) Champion")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PickemsColors.textSecondary)
                    Text(archive.championDisplayName ?? "TBD")
                        .font(.title3.bold())
                        .foregroundStyle(PickemsColors.textPrimary)
                    if let champ = archive.finalStandings.first {
                        Text("\(champ.seasonWins)-\(champ.seasonLosses) · \(archive.weekCount) weeks")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func careerRow(_ career: CareerRecord) -> some View {
        HStack(spacing: 12) {
            InitialsAvatar(
                initials: String(career.displayName.prefix(2)).uppercased(),
                colorHex: career.avatarColorHex,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(career.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PickemsColors.textPrimary)
                Text("\(career.seasonsPlayed) seasons · career \(career.recordLabel)")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)
            }
            Spacer()
            if career.titles > 0 {
                Label("\(career.titles)", systemImage: "crown.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.vertical, 4)
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
                                Text(String(archive.seasonYear))
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
