import Foundation

struct HelpTopic: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let tips: [String]

    init(id: String, title: String, message: String, tips: [String] = []) {
        self.id = id
        self.title = title
        self.message = message
        self.tips = tips
    }
}

enum PickemsHelp {
    // MARK: - Home

    static let homeOverview = HelpTopic(
        id: "home.overview",
        title: "Home",
        message: "Your command center for the current CFB week. Scores refresh automatically on game days.",
        tips: [
            "Pull down to refresh scores and week data.",
            "Tap Submit Picks or Leaderboard for quick navigation.",
            "Your slate games show pick results once games finish."
        ]
    )

    static let liveScores = HelpTopic(
        id: "home.liveScores",
        title: "Live Scores",
        message: "Game data comes from ESPN. Spreads are locked when your commissioner builds the slate.",
        tips: [
            "Your Slate highlights games you picked this week.",
            "Green checkmarks mean your spread pick won."
        ]
    )

    static let weekStatus = HelpTopic(
        id: "home.weekStatus",
        title: "Week Status",
        message: "Each week moves through phases from building the slate to scoring picks.",
        tips: [
            "Selection — members or commissioner choose games.",
            "Picking — everyone submits spread picks.",
            "Locked — games are in progress; picks are final.",
            "Scored — all games finished; standings updated."
        ]
    )

    static let standingsPreview = HelpTopic(
        id: "home.standings",
        title: "Standings Preview",
        message: "Shows the top three players for the current week. Full rankings live on the Groups tab.",
        tips: ["Batting average is wins ÷ (wins + losses)."]
    )

    // MARK: - Picks

    static let picksOverview = HelpTopic(
        id: "picks.overview",
        title: "Picks",
        message: "Make your weekly spread picks against the slate your group selected.",
        tips: [
            "Tap a team to select them against the spread.",
            "Submit before the deadline shown at the top.",
            "Draft picks save automatically as you tap."
        ]
    )

    static let nominations = HelpTopic(
        id: "picks.nominations",
        title: "Nominate Games",
        message: "Help build this week's slate by suggesting games for the group.",
        tips: [
            "Each member can nominate a limited number of games.",
            "When the slate is full, everyone moves to the picking phase.",
            "Commissioners can remove nominations or lock the slate early."
        ]
    )

    static let commissionerSlate = HelpTopic(
        id: "picks.commissionerSlate",
        title: "Build Slate",
        message: "As commissioner, you choose every game for the group this week.",
        tips: [
            "Browse ESPN games and tap to add them.",
            "Spreads are captured when the slate locks.",
            "Add games until you reach your configured slate size."
        ]
    )

    static let spreadPicks = HelpTopic(
        id: "picks.spread",
        title: "Spread Picks",
        message: "Pick the team you think will cover the point spread — not necessarily who wins outright.",
        tips: [
            "Example: Ohio State -7 means OSU must win by more than 7.",
            "A push (exact spread) is neither a win nor a loss.",
            "You must pick every slate game before submitting."
        ]
    )

    static let pickDeadline = HelpTopic(
        id: "picks.deadline",
        title: "Pick Deadline",
        message: "Your commissioner sets when picks lock — usually first kickoff or a custom time the day before.",
        tips: ["After the deadline, picks cannot be changed."]
    )

    // MARK: - Groups

    static let groupsOverview = HelpTopic(
        id: "groups.overview",
        title: "Groups",
        message: "Your private pick'em league. Switch between groups using the chips at the top.",
        tips: [
            "Share your invite code so friends can join.",
            "Toggle between weekly and season standings."
        ]
    )

    static let inviteFriends = HelpTopic(
        id: "groups.invite",
        title: "Invite Friends",
        message: "Send your league's 6-character invite code. Friends join from onboarding or when they sign in.",
        tips: ["Only people with the code can join your private league."]
    )

    static let leaderboard = HelpTopic(
        id: "groups.leaderboard",
        title: "Leaderboard",
        message: "Rankings based on spread pick record. This Week resets each slate; Season is cumulative.",
        tips: [
            "W-L is wins and losses against the spread.",
            "Tied players may need a commissioner tie-break decision."
        ]
    )

    static let commissionerSettings = HelpTopic(
        id: "groups.commissioner",
        title: "Commissioner Settings",
        message: "Control how your league selects games, pick deadlines, and tie-breakers.",
        tips: [
            "Member mode: everyone nominates games.",
            "Commissioner mode: you pick the full slate.",
            "Changes apply to future weeks."
        ]
    )

    // MARK: - Profile

    static let profileOverview = HelpTopic(
        id: "profile.overview",
        title: "Profile",
        message: "Manage your display name and notification preferences.",
        tips: [
            "Enable push notifications for deadline reminders and scored weeks.",
            "Your invite code is shown under League when you're in a group."
        ]
    )

    static let notifications = HelpTopic(
        id: "profile.notifications",
        title: "Notifications",
        message: "Pickems sends reminders before pick deadlines and updates when your week is scored.",
        tips: ["You can change notification settings anytime in iOS Settings → Pickems."]
    )

    // MARK: - Onboarding

    static let createGroup = HelpTopic(
        id: "onboarding.create",
        title: "Create a Group",
        message: "Start a private league. You'll be the commissioner and can invite friends with your code.",
        tips: ["You can configure slate size and rules after creating the group."]
    )

    static let joinGroup = HelpTopic(
        id: "onboarding.join",
        title: "Join a Group",
        message: "Enter the 6-character invite code from your commissioner.",
        tips: ["Codes are case-insensitive.", "Ask your commissioner to tap Invite Friends on the Groups tab."]
    )
}
