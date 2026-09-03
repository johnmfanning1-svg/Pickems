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
    /// Spread-pick lock policy. Product default is earliest slate kickoff (`firstKickoff`).
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

    enum CodingKeys: String, CodingKey {
        case selectionMode, selectionsPerMember, slateSize, pickDeadline, tieBreaker
        case customDeadlineHour, customDeadlineMinute
        case allowConfidencePick, allowLatePicks, latePickPenaltyWins
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
        latePickPenaltyWins: Int = 1
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
        latePickPenaltyWins: 1
    )
}
