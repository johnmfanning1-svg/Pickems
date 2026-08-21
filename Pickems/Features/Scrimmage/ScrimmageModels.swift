import Foundation

/// Scrimmage is a fully local, simulated tutorial week. Nothing in this
/// feature reads from or writes to Firestore, so scrimmage results can
/// never affect real records, standings, careers, or trophies.

/// The phases of the scrimmage flow, mirroring a real week's lifecycle
/// (picking → locked → live → scored) with tutorial framing around it.
enum ScrimmagePhase: Int, CaseIterable, Equatable {
    /// Welcome + explanation of how a week works.
    case intro
    /// User makes ATS picks on the fake slate (mirrors `WeekStatus.picking`).
    case picking
    /// Picks are in; brief "locked" beat (mirrors `WeekStatus.locked`).
    case locked
    /// Games play out with animated live scores over a few seconds.
    case live
    /// Week scored: user's rigged 4-0 record revealed per game.
    case results
    /// Leaderboard with the user on top.
    case standings
    /// Trophy + "doesn't count toward real records" disclaimer + CTA.
    case celebration
}

/// Where the scrimmage was launched from; controls the final CTA copy.
enum ScrimmageContext {
    /// Launched from onboarding, before the user has joined a group.
    case onboarding
    /// Replayed from the Profile tab as a refresher.
    case replay
}

/// A row in the scrimmage's fake leaderboard.
struct ScrimmageStanding: Identifiable, Equatable {
    let id: String
    let displayName: String
    let wins: Int
    let losses: Int
    let rank: Int
    let isUser: Bool
}

/// A fake league member (bot) that "plays" alongside the user.
struct ScrimmageBot: Identifiable, Equatable {
    let id: String
    let displayName: String
    /// How many of the user's picks this bot agrees with (0...slate size).
    /// Because the user always goes 4-0, a bot's record is
    /// `agreesWithUserCount` wins and `slateSize - agreesWithUserCount` losses.
    let agreesWithUserCount: Int
}

enum ScrimmageDefaults {
    /// UserDefaults key marking that the user finished a scrimmage at least once.
    static let completedKey = "pickems.scrimmage.completed"
    /// Fake league name shown throughout the tutorial.
    static let leagueName = "The Practice Squad"
}
