import SwiftUI

// MARK: - Intro

struct ScrimmageIntroPhase: View {
    let onStart: () -> Void
    @Environment(\.themePalette) private var theme

    private let bullets: [(icon: String, title: String, detail: String)] = [
        ("calendar", "Slate is set", "Your league gets a handful of games each week."),
        ("hand.tap.fill", "Everyone picks ATS", "Tap the team you think will beat the spread."),
        ("lock.fill", "Picks lock at kickoff", "Once games start, picks are final."),
        ("chart.bar.fill", "Wins update standings", "Correct covers move you up the leaderboard."),
    ]

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "figure.american.football")
                    .font(.system(size: 44))
                    .foregroundStyle(theme.accent)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                Text("Welcome to Scrimmage")
                    .font(.title2.bold())
                    .foregroundStyle(PickemsColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("A quick practice week so you can learn the rhythm before it counts.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: bullet.icon)
                            .font(.title3)
                            .foregroundStyle(theme.accent)
                            .frame(width: 28)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bullet.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PickemsColors.textPrimary)
                            Text(bullet.detail)
                                .font(.caption)
                                .foregroundStyle(PickemsColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PickemsColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            ContextualTipBanner(
                icon: "info.circle.fill",
                message: "Scrimmage is practice only — results never count toward real records or trophies."
            )
            .padding(.horizontal, -16)

            PrimaryButton(
                title: "Start Picking",
                accessibilityHint: "Begins the practice picking phase"
            ) {
                onStart()
            }
        }
        .padding(.horizontal)
        .pickemsAppear()
    }
}

// MARK: - Picking

struct ScrimmagePickingPhase: View {
    let games: [SlateGame]
    let draftPicks: [String: String]
    let allPicksMade: Bool
    let onSelect: (String, String) -> Void
    let onSubmit: () -> Void

    private var pickedCount: Int { draftPicks.count }

    var body: some View {
        VStack(spacing: 16) {
            ContextualTipBanner(
                icon: "hand.tap.fill",
                message: "Tap a team you think will beat the spread"
            )

            Text("\(pickedCount) of \(games.count) picked")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .accessibilityLabel("\(pickedCount) of \(games.count) games picked")

            ForEach(games) { game in
                GamePickRow(
                    game: game,
                    selectedTeamId: draftPicks[game.id],
                    onSelect: { teamId in
                        onSelect(game.id, teamId)
                    }
                )
                .padding(.horizontal)
            }

            PrimaryButton(
                title: "Submit Picks",
                accessibilityHint: allPicksMade
                    ? "Locks your picks and starts the live simulation"
                    : "Pick every game before submitting"
            ) {
                onSubmit()
            }
            .disabled(!allPicksMade)
            .opacity(allPicksMade ? 1 : 0.45)
            .padding(.horizontal)
            .accessibilityValue(allPicksMade ? "Ready" : "Disabled until all picks are made")
        }
    }
}

// MARK: - Locked / Live

struct ScrimmageLivePhase: View {
    let phase: ScrimmagePhase
    let games: [SlateGame]
    let draftPicks: [String: String]

    var body: some View {
        VStack(spacing: 16) {
            if phase == .locked {
                ContextualTipBanner(
                    icon: "lock.fill",
                    message: "Picks locked! In a real week this happens at kickoff."
                )
            } else {
                HStack {
                    StatusBadge(text: "In Progress", color: PickemsColors.warning)
                    Spacer()
                    Text("Watching scores update…")
                        .font(.caption)
                        .foregroundStyle(PickemsColors.textSecondary)
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
            }

            ForEach(games) { game in
                ScrimmageScoreCard(
                    game: game,
                    pickedTeamId: draftPicks[game.id],
                    showsResult: false
                )
                .padding(.horizontal)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: games.map(\.homeScore))
        .animation(.easeInOut(duration: 0.25), value: games.map(\.awayScore))
    }
}

// MARK: - Results

struct ScrimmageResultsPhase: View {
    let games: [SlateGame]
    let draftPicks: [String: String]
    let userRecord: (wins: Int, losses: Int)
    let onContinue: () -> Void
    @Environment(\.themePalette) private var theme

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("You went \(userRecord.wins)-\(userRecord.losses)!")
                    .font(PickemsTypography.display(28))
                    .foregroundStyle(theme.accent)
                    .multilineTextAlignment(.center)

                Text("Every cover counted. Here's how each pick finished.")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            ForEach(games) { game in
                ScrimmageScoreCard(
                    game: game,
                    pickedTeamId: draftPicks[game.id],
                    showsResult: true
                )
                .padding(.horizontal)
            }

            ContextualTipBanner(
                icon: "icloud.fill",
                message: "In a real week, a Cloud scoring job updates results automatically when games go final."
            )

            PrimaryButton(
                title: "See Standings",
                accessibilityHint: "Shows the practice league leaderboard"
            ) {
                onContinue()
            }
            .padding(.horizontal)
        }
        .pickemsAppear()
    }
}

// MARK: - Standings

struct ScrimmageStandingsPhase: View {
    let standings: [ScrimmageStanding]
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("Week Standings")
                    .font(.title2.bold())
                    .foregroundStyle(PickemsColors.textPrimary)

                Text("You topped \(ScrimmageDefaults.leagueName).")
                    .font(.subheadline)
                    .foregroundStyle(PickemsColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            ScrimmageStandingsList(standings: standings)
                .padding(.horizontal)

            PrimaryButton(
                title: "Continue",
                accessibilityHint: "Continues to the celebration"
            ) {
                onContinue()
            }
            .padding(.horizontal)
        }
        .pickemsAppear()
    }
}

// MARK: - Celebration

struct ScrimmageCelebrationPhase: View {
    let context: ScrimmageContext
    let userRecord: (wins: Int, losses: Int)
    let onFinish: () -> Void
    let onReplay: () -> Void

    @Environment(\.themePalette) private var theme
    @State private var trophyAppeared = false

    private var finishTitle: String {
        context == .onboarding ? "Join a Real League" : "Done"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            Image(systemName: "trophy.fill")
                .font(.system(size: 88))
                .foregroundStyle(theme.accent)
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(trophyAppeared ? 1 : 0.35)
                .rotationEffect(.degrees(trophyAppeared ? 0 : -18))
                .opacity(trophyAppeared ? 1 : 0)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("You won the week!")
                    .font(PickemsTypography.display(32))
                    .foregroundStyle(PickemsColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("\(userRecord.wins)-\(userRecord.losses) in \(ScrimmageDefaults.leagueName)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.accent)
            }
            .opacity(trophyAppeared ? 1 : 0)
            .offset(y: trophyAppeared ? 0 : 12)

            Text("Scrimmage results never count toward real records, standings, or trophies.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PickemsColors.warning)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
                .background(PickemsColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PickemsColors.warning.opacity(0.35), lineWidth: 1)
                )
                .accessibilityLabel("Disclaimer: Scrimmage results never count toward real records, standings, or trophies.")

            VStack(spacing: 12) {
                PrimaryButton(
                    title: finishTitle,
                    accessibilityHint: context == .onboarding
                        ? "Finishes scrimmage and returns to join a league"
                        : "Finishes scrimmage and returns to your profile"
                ) {
                    onFinish()
                }

                SecondaryButton("Replay Scrimmage", icon: "arrow.counterclockwise") {
                    onReplay()
                }
                .accessibilityHint("Restarts the practice week from the beginning")
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                trophyAppeared = true
            }
            PickemsHaptics.success()
        }
        .onDisappear {
            trophyAppeared = false
        }
    }
}

// MARK: - Shared score card

struct ScrimmageScoreCard: View {
    let game: SlateGame
    let pickedTeamId: String?
    var showsResult: Bool
    @Environment(\.themePalette) private var theme

    var body: some View {
        PickemsCard {
            VStack(spacing: 12) {
                HStack {
                    teamColumn(
                        abbreviation: game.awayTeamAbbreviation,
                        logo: game.awayTeamLogoURL,
                        score: game.awayScore,
                        teamId: game.awayTeamId
                    )

                    VStack(spacing: 4) {
                        Text("@")
                            .foregroundStyle(PickemsColors.textSecondary)
                        statusLabel
                    }
                    .frame(width: 72)

                    teamColumn(
                        abbreviation: game.homeTeamAbbreviation,
                        logo: game.homeTeamLogoURL,
                        score: game.homeScore,
                        teamId: game.homeTeamId
                    )
                }

                HStack {
                    if let pickedTeamId {
                        Text("Your pick: \(abbreviation(for: pickedTeamId))")
                            .font(.caption)
                            .foregroundStyle(PickemsColors.textSecondary)
                    }
                    Spacer()
                    if showsResult {
                        Label("Win", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PickemsColors.success)
                            .accessibilityLabel("Win")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch game.status {
        case .scheduled:
            Text("Upcoming")
                .font(.caption2)
                .foregroundStyle(PickemsColors.textSecondary)
        case .inProgress:
            Text("Live")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PickemsColors.warning)
                .pickemsPulse()
        case .final:
            Text("Final")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PickemsColors.textSecondary)
        }
    }

    private func teamColumn(abbreviation: String, logo: String?, score: Int?, teamId: String) -> some View {
        let isPicked = pickedTeamId == teamId
        return VStack(spacing: 6) {
            if let logo, let url = URL(string: logo) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "football.fill")
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            }

            Text(abbreviation)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PickemsColors.textPrimary)

            Text(score.map(String.init) ?? "—")
                .font(PickemsTypography.display(22))
                .foregroundStyle(isPicked ? theme.accent : PickemsColors.textPrimary)
                .contentTransition(.numericText())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(isPicked ? theme.accent.opacity(0.22) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isPicked ? theme.accent : Color.clear, lineWidth: 2)
        )
    }

    private func abbreviation(for teamId: String) -> String {
        if teamId == game.homeTeamId { return game.homeTeamAbbreviation }
        if teamId == game.awayTeamId { return game.awayTeamAbbreviation }
        return teamId
    }

    private var accessibilitySummary: String {
        let awayScore = game.awayScore.map(String.init) ?? "no score"
        let homeScore = game.homeScore.map(String.init) ?? "no score"
        let pick = pickedTeamId.map { "Your pick \(abbreviation(for: $0))." } ?? ""
        let result = showsResult ? " Win." : ""
        return "\(game.awayTeamAbbreviation) \(awayScore) at \(game.homeTeamAbbreviation) \(homeScore). \(pick)\(result)"
    }
}
