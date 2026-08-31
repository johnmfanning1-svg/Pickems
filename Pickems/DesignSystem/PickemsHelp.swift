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
            "The board opens on Top 25. Swipe the chips for My Picks, Group, All, Power 4, or a conference.",
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
            "Green checkmarks mean your Pickem won.",
            "A lock next to a spread is the Pickems line used for scoring. The number in parentheses is ESPN’s live line, for reference."
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
            "See who's in shows how many Pickems each member has made — not who they picked.",
            "After Pickems lock, this tab shows the league chart. Expand Your Pickems to review your own picks."
        ]
    )

    static let leaguePickems = HelpTopic(
        id: "picks.leagueBoard",
        title: "League Pickems",
        message: "Once Pickems lock, everyone can see the chart: games as rows, members as columns. Colors update as games go.",
        tips: [
            "Before lock, this screen shows a countdown — picks stay hidden.",
            "An asterisk next to a team means that team is favored — the spread applies to them.",
            "A lock is the Pickems line. The number in parentheses is ESPN’s live line, for reference.",
            "Tap the expand arrows to view the chart fullscreen in landscape.",
            "After lock, open Season History to browse past weeks' charts."
        ]
    )

    static let seasonHistory = HelpTopic(
        id: "picks.seasonHistory",
        title: "Season History",
        message: "Browse locked and scored weeks as league Pickems charts. Choose a week to see how everyone picked.",
        tips: [
            "Your record for that week sits above the chart.",
            "Weeks that have not locked yet show a countdown instead of an empty chart."
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
            "A lock marks the Pickems line. The number in parentheses is ESPN’s live line, for reference — scoring uses the locked line.",
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
            "Share your invite code so friends can join — unless the commissioner locked invites to themselves.",
            "Toggle between weekly and season standings.",
            "View League Pickems opens the chart after lock, or a countdown until then.",
            "Rivalry compares your weekly record with another member.",
            "Dynasty opens champions and career records."
        ]
    )

    static let inviteFriends = HelpTopic(
        id: "groups.invite",
        title: "Invite Friends",
        message: "Send your league's 4–8 character invite code. Friends join from onboarding or when they sign in.",
        tips: [
            "Only people with the code can join your private league.",
            "On a private league, the commissioner can turn on Only commissioner can invite so members ask them to share the code."
        ]
    )

    static let leaderboard = HelpTopic(
        id: "groups.leaderboard",
        title: "Leaderboard",
        message: "Rankings based on Pickem record. This Week resets each slate; Season is cumulative.",
        tips: [
            "W-L is wins and losses against the spread.",
            "Tied players may need a commissioner tie-break decision.",
            "Leagues with more than 10 members show Full ranking under the This Week / Season picker, then the top 10."
        ]
    )

    static let commissionerSettings = HelpTopic(
        id: "groups.commissioner",
        title: "Commissioner Settings",
        message: "Choose either Selections-per-member or games-per-week — not both.",
        tips: [
            "Members Select: set how many games each person submits.",
            "Commissioner Selects: set total games per week and build the slate yourself.",
            "Changes apply to future weeks. Set a Selection deadline each week in member mode.",
            "On a private league, Only commissioner can invite hides Invite Friends for members."
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
            "Push alerts cover Selection and Pickems deadlines — toggle each in Profile, or change iOS permission in Settings.",
            "Home Screen widget and Live Activities follow the league you pick under Home Screen & Live Activity."
        ]
    )

    static let widgetAndLiveActivity = HelpTopic(
        id: "profile.widgetLiveActivity",
        title: "Home Screen & Live Activity",
        message: "Choose which league the Home Screen widget and Live Activities show. Switching leagues in the app does not change this until you pick a different league here.",
        tips: [
            "The widget and lock-screen Live Activity update as soon as you change this setting.",
            "If you leave that league, Pickems falls back to another league you are in, or clears the widget."
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
