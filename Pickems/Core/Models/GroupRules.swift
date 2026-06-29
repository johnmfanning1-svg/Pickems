import Foundation

enum SelectionMode: String, Codable, CaseIterable, Identifiable {
    case commissioner
    case member

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commissioner: return "Commissioner Selects"
        case .member: return "Members Nominate"
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
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firstKickoff: return "First Game Kickoff"
        case .custom: return "Custom Time"
        }
    }
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
    var selectionMode: SelectionMode
    var selectionsPerMember: Int
    var slateSize: Int
    var pickDeadline: DeadlinePolicy
    var tieBreaker: TieBreakerPolicy
    var customDeadlineHour: Int
    var customDeadlineMinute: Int

    enum CodingKeys: String, CodingKey {
        case selectionMode, selectionsPerMember, slateSize, pickDeadline, tieBreaker
        case customDeadlineHour, customDeadlineMinute
    }

    init(
        selectionMode: SelectionMode,
        selectionsPerMember: Int,
        slateSize: Int,
        pickDeadline: DeadlinePolicy,
        tieBreaker: TieBreakerPolicy,
        customDeadlineHour: Int = 18,
        customDeadlineMinute: Int = 0
    ) {
        self.selectionMode = selectionMode
        self.selectionsPerMember = selectionsPerMember
        self.slateSize = slateSize
        self.pickDeadline = pickDeadline
        self.tieBreaker = tieBreaker
        self.customDeadlineHour = customDeadlineHour
        self.customDeadlineMinute = customDeadlineMinute
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
    }

    static let `default` = GroupRules(
        selectionMode: .member,
        selectionsPerMember: 3,
        slateSize: 12,
        pickDeadline: .firstKickoff,
        tieBreaker: .commissionerOverride,
        customDeadlineHour: 18,
        customDeadlineMinute: 0
    )
}
