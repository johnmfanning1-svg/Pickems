import SwiftUI

/// Leagues-tab destination: league chart after lock, countdown until then.
struct LeaguePickemsEntryView: View {
    @Environment(AppState.self) private var appState

    private var week: WeekSummary? {
        appState.groupService.currentWeek
    }

    private var showsBoard: Bool {
        guard let week else { return false }
        return WeekTransition.pickemsShouldShowLeagueBoard(week)
    }

    var body: some View {
        Group {
            if showsBoard {
                GroupPicksView()
            } else {
                pendingLockContent
            }
        }
        .toolbar {
            HelpToolbarItem(topic: PickemsHelp.leaguePickems)
        }
    }

    private var pendingLockContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let week {
                    if let deadline = week.pickDeadline {
                        PickDeadlineBanner(
                            deadline: deadline,
                            isRolling: week.isRollingLock
                        )
                        pendingCaption(
                            week.isRollingLock
                                ? "Each game's picks show here at that game's kickoff. Later games stay hidden."
                                : "Everyone's Pickems show here after lock. Picks stay hidden until then."
                        )
                    } else if let selectionDeadline = week.selectionDeadline {
                        SelectionDeadlineBanner(deadline: selectionDeadline)
                        EmptyStateView(
                            icon: "lock.open",
                            title: "Pickems lock after the slate is set",
                            message: "Once Selections are in, you'll see a countdown to lock here.",
                            help: PickemsHelp.leaguePickems
                        )
                    } else {
                        EmptyStateView(
                            icon: "lock.open",
                            title: "Pickems lock after the slate is set",
                            message: week.status == .selection
                                ? "Finish Selections first. The league chart opens after Pickems lock."
                                : "You'll see a countdown here once this week's lock time is set.",
                            help: PickemsHelp.leaguePickems
                        )
                    }
                } else {
                    EmptyStateView(
                        icon: "person.3",
                        title: "No Active Week",
                        message: "Join a league to see League Pickems.",
                        help: PickemsHelp.leaguePickems
                    )
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("League Pickems")
        .navigationBarTitleDisplayMode(.inline)
        .pickemsScreenBackground()
    }

    private func pendingCaption(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(PickemsColors.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
    }
}
