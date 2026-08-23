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
            "Tap Make Selections or Make Pickems to jump to this week's action.",
            "Your slate games show Pickem results once games finish."
        ]
    )

    static let liveScores = HelpTopic(
        id: "home.liveScores",
        title: "Live Scores",
        message: "Game data comes from ESPN. Spreads are locked when your commissioner builds the slate.",
        tips: [
            "Your Slate highlights games on your slate this week.",
            "Green checkmarks mean your Pickem won."
        ]
    )

    static let weekStatus = HelpTopic(
        id: "home.weekStatus",
        title: "Week Status",
        message: "Each week moves through phases from building the slate to scoring Pickems.",
        tips: [
            "Selection — members or commissioner choose games.",
            "Pickems — everyone submits Pickems against the spread.",
            "Locked — games are in progress; Pickems are final.",
            "Scored — all games finished; standings updated."
        ]
    )

    static let standingsPreview = HelpTopic(
        id: "home.standings",
        title: "Standings Preview",
        message: "Shows the top three players for the current week. Full rankings live on the Leagues tab.",
        tips: ["Batting average is wins ÷ (wins + losses)."]
    )

    // MARK: - Picks

    static let picksOverview = HelpTopic(
        id: "picks.overview",
        title: "Pickems",
        message: "Make your weekly Pickems against the slate your league selected.",
        tips: [
            "Tap a team to select them against the spread.",
            "Submit before the deadline shown at the top.",
            "Draft Pickems save automatically as you tap.",
            "Pickems stay locked until Selections are done or the Selection deadline passes.",
            "See who's in shows how many Pickems each member has made — not who they picked."
        ]
    )

    static let submissionStatus = HelpTopic(
        id: "picks.submissionStatus",
        title: "Who's in",
        message: "A count of how many Pickems each member has made this week, and whether they have submitted.",
        tips: [
            "Other members' actual picks stay hidden until the first kickoff or an early lock.",
            "Submitted means they locked in a full slate.",
            "In progress means they have started but have not submitted yet."
        ]
    )

    static let nominations = HelpTopic(
        id: "picks.nominations",
        title: "Selections",
        message: "Pick this week's games for your league. Already-selected games are greyed out with the member who chose them.",
        tips: [
            "Each member selects up to the league’s per-member limit.",
            "Clear a Selection before the deadline, then pick a replacement.",
            "Pickems do not open just because the slate is full — wait for the deadline or a commissioner lock-early."
        ]
    )

    static let commissionerSlate = HelpTopic(
        id: "picks.commissionerSlate",
        title: "Make Selections",
        message: "As commissioner, you choose every game for the league this week.",
        tips: [
            "Browse ESPN games and tap to add them.",
            "Add games until you reach your games-per-week setting.",
            "Pickems lock at the earliest kickoff on the slate."
        ]
    )

    static let selectionDeadline = HelpTopic(
        id: "picks.selectionDeadline",
        title: "Selection Deadline",
        message: "Set when members must finish making Selections so there’s still time to make Pickems before kickoff.",
        tips: [
            "You’ll get a push at the start of each week to set this.",
            "After it passes, you can fill remaining games or open the week with fewer.",
            "Pickems still lock at the earliest slate kickoff."
        ]
    )

    static let spreadPicks = HelpTopic(
        id: "picks.spread",
        title: "Pickems",
        message: "Pick the team you think will cover the point spread — not necessarily who wins outright.",
        tips: [
            "Example: Ohio State -7 means OSU must win by more than 7.",
            "Tap a selected team to clear that Pickem. The Selection (the game) stays on the slate.",
            "A push (exact spread) is neither a win nor a loss.",
            "You must make a Pickem on every slate game before submitting."
        ]
    )

    static let pickDeadline = HelpTopic(
        id: "picks.deadline",
        title: "Pickems Deadline",
        message: "Pickems lock at the start time of the earliest game on this week’s slate — unless the commissioner sets a custom deadline.",
        tips: [
            "Commissioners can extend or reopen the deadline from the Pickems tab.",
            "After the deadline, Pickems cannot be changed unless the commissioner unlocks them."
        ]
    )

    // MARK: - Groups

    static let groupsOverview = HelpTopic(
        id: "groups.overview",
        title: "Leagues",
        message: "Your private pick'em league. Switch leagues using the chips at the top. Selections and Pickems live on their own tabs.",
        tips: [
            "Share your invite code so friends can join.",
            "Toggle between weekly and season standings."
        ]
    )

    static let inviteFriends = HelpTopic(
        id: "groups.invite",
        title: "Invite Friends",
        message: "Send your league's 4–8 character invite code. Friends join from onboarding or when they sign in.",
        tips: ["Only people with the code can join your private league."]
    )

    static let leaderboard = HelpTopic(
        id: "groups.leaderboard",
        title: "Leaderboard",
        message: "Rankings based on Pickem record. This Week resets each slate; Season is cumulative.",
        tips: [
            "W-L is wins and losses against the spread.",
            "Tied players may need a commissioner tie-break decision."
        ]
    )

    static let commissionerSettings = HelpTopic(
        id: "groups.commissioner",
        title: "Commissioner Settings",
        message: "Choose either Selections-per-member or games-per-week — not both.",
        tips: [
            "Members Select: set how many games each person submits.",
            "Commissioner Selects: set total games per week and build the slate yourself.",
            "Changes apply to future weeks. Set a Selection deadline each week in member mode."
        ]
    )

    // MARK: - Profile

    static let profileOverview = HelpTopic(
        id: "profile.overview",
        title: "Profile",
        message: "Manage your name, unique username, team theme, leagues, and notification preferences.",
        tips: [
            "First and last name identify your account; username is what friends see in leagues.",
            "Usernames must be unique (letters, numbers, underscore).",
            "Push alerts cover Selection and Pickems deadlines — toggle each in Profile, or change iOS permission in Settings."
        ]
    )

    static let notifications = HelpTopic(
        id: "profile.notifications",
        title: "Notifications",
        message: "Turn Selection and Pickems deadline reminders on or off. Game-final and scored-week alerts still follow iOS permission.",
        tips: [
            "Turning a toggle on asks for iOS permission if you have not allowed it yet.",
            "If iOS blocked alerts, Open Settings to re-enable them for Pickems.",
            "You can turn system notifications off anytime in iOS Settings → Pickems → Notifications."
        ]
    )

    // MARK: - Onboarding

    static let createGroup = HelpTopic(
        id: "onboarding.create",
        title: "Create a League",
        message: "Start a private league. You'll be the commissioner and can invite friends with your code.",
        tips: ["You can configure slate size and rules after creating the league."]
    )

    static let joinGroup = HelpTopic(
        id: "onboarding.join",
        title: "Join a League",
        message: "Enter the 4–8 character invite code from your commissioner.",
        tips: ["Codes are case-insensitive.", "Ask your commissioner to tap Invite Friends on the Leagues tab."]
    )
}

enum SelectionPhaseCopy {
    static let confirmSubmit =
        "You can still remove a Selection and pick a different game until the Selection deadline."

    static let swapHint =
        "Want a different game? Remove one below, then tap Select Game."

    static func submittedCaption(gameCount: Int, week: WeekSummary) -> String {
        let games = "\(gameCount) game\(gameCount == 1 ? "" : "s")"
        if let deadline = week.selectionDeadline {
            return "Your \(games) \(gameCount == 1 ? "is" : "are") in. Tap Edit Selections to swap games until \(PickDeadlineCalculator.lockTimeLabel(for: deadline))."
        }
        return "Your \(games) \(gameCount == 1 ? "is" : "are") in. Tap Edit Selections to swap games until the Selection deadline."
    }

    static func memberDeadlineBanner(hasSelections: Bool, deadline: Date, deadlinePassed: Bool) -> String {
        if deadlinePassed {
            return "Selection deadline passed. Waiting on your commissioner to open the week."
        }
        if hasSelections {
            return "You can swap Selections until \(PickDeadlineCalculator.lockTimeLabel(for: deadline))."
        }
        return "Select by \(PickDeadlineCalculator.lockTimeLabel(for: deadline))."
    }
}
