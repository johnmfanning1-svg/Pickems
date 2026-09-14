import Foundation

enum SelectionMode: String, Codable, CaseIterable, Identifiable {
    case commissioner
    case member

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commissioner: return "Commissioner Selects"
        case .member: return "Members Select"
        }
    }
}

enum WeekStatus: String, Codable {
    case selection
    case picking
    case locked
    case scored
}

enum DeadlinePolicy: String, Codable, CaseIterable, Identifiable {
    case firstKickoff
    case rolling
    /// Legacy unused policy. Kept for decode; treated as first-kickoff.
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstKickoff: return "First Game Kickoff"
        case .rolling: return "Rolling — each game at kickoff"
        case .custom: return "Custom Time"
        }
    }

    /// Commissioner picker — `custom` stays out of the UI.
    static var lockModeCases: [DeadlinePolicy] { [.firstKickoff, .rolling] }

    var lockModeDisplayName: String {
        switch self {
        case .firstKickoff: return "Entire slate at first kickoff"
        case .rolling: return "Rolling — each game at kickoff"
        case .custom: return "Custom Time"
        }
    }

    var isRolling: Bool { self == .rolling }
}

enum TieBreakerPolicy: String, Codable, CaseIterable, Identifiable {
    case commissionerOverride
    case headToHead

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commissionerOverride: return "Commissioner Override"
        case .headToHead: return "Head-to-Head"
        }
    }
}

/// How Pickems are graded. Stored on `groups/{id}.rules.pickMode`.
/// Missing on existing leagues → `.ats` so ATS scoring stays unchanged.
/// ATS leagues may also set `weeks/{id}.pickMode` to `.straightUp` for one week.
enum PickMode: String, Codable, CaseIterable, Identifiable {
    case ats
    case straightUp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ats: return "Against the Spread"
        case .straightUp: return "Straight Up"
        }
    }

    /// Spreads stay off every Straight Up surface — including live ESPN lines on slate games.
    var showsSpreads: Bool { self == .ats }

    var pickemsSectionTitle: String {
        switch self {
        case .ats: return "Spread Pickems"
        case .straightUp: return "Straight Up Pickems"
        }
    }

    var recordPhrase: String {
        switch self {
        case .ats: return "against the spread"
        case .straightUp: return "straight up"
        }
    }

    var leagueChartSubtitle: String {
        switch self {
        case .ats: return "Everyone's picks against the spread"
        case .straightUp: return "Everyone's outright winner picks"
        }
    }

    var createFooter: String {
        switch self {
        case .ats:
            return "Pick which team covers the point spread. League type is set at create and cannot be changed mid-season."
        case .straightUp:
            return "Pick the outright winner. Spreads are hidden, and a game tie is a push. League type is set at create and cannot be changed mid-season."
        }
    }

    var coverMomentWinTitle: String {
        switch self {
        case .ats: return "Covered"
        case .straightUp: return "Won"
        }
    }

    var gameFinalWinTitle: String {
        switch self {
        case .ats: return "You covered"
        case .straightUp: return "You won"
        }
    }
}

struct GroupRules: Codable, Equatable {
    /// Who builds the weekly slate. Either/or with the numeric knobs below:
    /// - `.member`: only `selectionsPerMember` is active; expected slate size is derived at week mint.
    /// - `.commissioner`: only `slateSize` is active; `selectionsPerMember` is ignored.
    var selectionMode: SelectionMode
    /// Member mode only — nominations each member may submit.
    var selectionsPerMember: Int
    /// Commissioner mode only — target games per week. In member mode this value on
    /// `GroupRules` is ignored; the week snapshot stores the derived allowance.
    var slateSize: Int
    /// Pickems lock policy. Product default is earliest slate kickoff (`firstKickoff`).
    /// `rolling` locks each game at its own kickoff. `custom` is legacy unused.
    var pickDeadline: DeadlinePolicy
    var tieBreaker: TieBreakerPolicy
    var customDeadlineHour: Int
    var customDeadlineMinute: Int
    /// Each member may mark one slate game as double-weight.
    var allowConfidencePick: Bool
    /// Allow submissions after deadline with a win penalty.
    var allowLatePicks: Bool
    var latePickPenaltyWins: Int
    /// ATS (default) vs Straight Up. Existing docs without this field decode as `.ats`.
    var pickMode: PickMode

    /// Expected unique games for a week under the active mode.
    /// Member mode is always `members × Selections per person`, never the unused
    /// `slateSize` default (12) left over from commissioner-mode config.
    func expectedSlateSize(memberCount: Int) -> Int {
        switch selectionMode {
        case .member:
            return max(1, max(memberCount, 1) * max(selectionsPerMember, 1))
        case .commissioner:
            return max(1, slateSize)
        }
    }

    var showsSpreads: Bool { pickMode.showsSpreads }

    enum CodingKeys: String, CodingKey {
        case selectionMode, selectionsPerMember, slateSize, pickDeadline, tieBreaker
        case customDeadlineHour, customDeadlineMinute
        case allowConfidencePick, allowLatePicks, latePickPenaltyWins
        case pickMode
    }

    init(
        selectionMode: SelectionMode,
        selectionsPerMember: Int,
        slateSize: Int,
        pickDeadline: DeadlinePolicy,
        tieBreaker: TieBreakerPolicy,
        customDeadlineHour: Int = 18,
        customDeadlineMinute: Int = 0,
        allowConfidencePick: Bool = false,
        allowLatePicks: Bool = false,
        latePickPenaltyWins: Int = 1,
        pickMode: PickMode = .ats
    ) {
        self.selectionMode = selectionMode
        self.selectionsPerMember = selectionsPerMember
        self.slateSize = slateSize
        self.pickDeadline = pickDeadline
        self.tieBreaker = tieBreaker
        self.customDeadlineHour = customDeadlineHour
        self.customDeadlineMinute = customDeadlineMinute
        self.allowConfidencePick = allowConfidencePick
        self.allowLatePicks = allowLatePicks
        self.latePickPenaltyWins = latePickPenaltyWins
        self.pickMode = pickMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectionMode = try container.decode(SelectionMode.self, forKey: .selectionMode)
        selectionsPerMember = try container.decode(Int.self, forKey: .selectionsPerMember)
        slateSize = try container.decode(Int.self, forKey: .slateSize)
        pickDeadline = try container.decode(DeadlinePolicy.self, forKey: .pickDeadline)
        tieBreaker = try container.decode(TieBreakerPolicy.self, forKey: .tieBreaker)
        customDeadlineHour = try container.decodeIfPresent(Int.self, forKey: .customDeadlineHour) ?? 18
        customDeadlineMinute = try container.decodeIfPresent(Int.self, forKey: .customDeadlineMinute) ?? 0
        allowConfidencePick = try container.decodeIfPresent(Bool.self, forKey: .allowConfidencePick) ?? false
        allowLatePicks = try container.decodeIfPresent(Bool.self, forKey: .allowLatePicks) ?? false
        latePickPenaltyWins = try container.decodeIfPresent(Int.self, forKey: .latePickPenaltyWins) ?? 1
        pickMode = try container.decodeIfPresent(PickMode.self, forKey: .pickMode) ?? .ats
    }

    static let `default` = GroupRules(
        selectionMode: .member,
        selectionsPerMember: 3,
        slateSize: 12,
        pickDeadline: .firstKickoff,
        tieBreaker: .commissionerOverride,
        customDeadlineHour: 18,
        customDeadlineMinute: 0,
        allowConfidencePick: false,
        allowLatePicks: false,
        latePickPenaltyWins: 1,
        pickMode: .ats
    )
}
