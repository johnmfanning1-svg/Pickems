import Foundation

/// One appointed week-operator seat. At most one of each per league.
enum LeagueCoordinatorRole: String, Codable, Equatable, Hashable, Identifiable, Sendable {
    case oc
    case dc

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .oc: return "OC"
        case .dc: return "DC"
        }
    }

    var title: String {
        switch self {
        case .oc: return "Offensive Coordinator"
        case .dc: return "Defensive Coordinator"
        }
    }

    var accessibilityLabel: String { title }

    var systemImage: String {
        switch self {
        case .oc: return "football.fill"
        case .dc: return "shield.fill"
        }
    }
}

/// `{ oc: uid, dc: uid }` on `groups/{leagueId}.coordinators`.
/// Missing keys mean the seat is empty. A missing map means no coordinators.
struct LeagueCoordinators: Codable, Equatable, Hashable, Sendable {
    var oc: String?
    var dc: String?

    init(oc: String? = nil, dc: String? = nil) {
        self.oc = oc
        self.dc = dc
    }

    var isEmpty: Bool { oc == nil && dc == nil }

    func holder(of role: LeagueCoordinatorRole) -> String? {
        switch role {
        case .oc: return oc
        case .dc: return dc
        }
    }

    func role(for userId: String) -> LeagueCoordinatorRole? {
        if oc == userId { return .oc }
        if dc == userId { return .dc }
        return nil
    }

    func clearing(_ userId: String) -> LeagueCoordinators {
        var copy = self
        if copy.oc == userId { copy.oc = nil }
        if copy.dc == userId { copy.dc = nil }
        return copy
    }

    /// Drop seats that rules would ignore: non-members, the commissioner, or the same person twice.
    func normalized(memberIds: [String], commissionerId: String) -> LeagueCoordinators {
        func keep(_ userId: String?) -> String? {
            guard let userId, userId != commissionerId, memberIds.contains(userId) else { return nil }
            return userId
        }
        var next = LeagueCoordinators(oc: keep(oc), dc: keep(dc))
        if next.oc != nil, next.oc == next.dc {
            next.dc = nil
        }
        return next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        oc = Self.uid(container, .oc)
        dc = Self.uid(container, .dc)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(oc, forKey: .oc)
        try container.encodeIfPresent(dc, forKey: .dc)
    }

    private enum CodingKeys: String, CodingKey {
        case oc
        case dc
    }

    /// A wrong-typed slot decodes as empty so one bad field cannot drop the league.
    private static func uid(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> String? {
        do {
            guard let value = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}

enum LeagueActorRole: Equatable, Sendable {
    case commissioner
    case coordinator(LeagueCoordinatorRole)
    case member

    var canOperateWeek: Bool {
        switch self {
        case .commissioner, .coordinator: return true
        case .member: return false
        }
    }

    var permissions: LeaguePermissions {
        switch self {
        case .commissioner:
            return LeaguePermissions(
                operateWeek: true,
                appointCoordinators: true,
                editLeagueRules: true,
                changeScoringMode: true,
                changeRollingLock: true,
                removeMembers: true,
                deleteLeague: true,
                transferCommissioner: true,
                billingOrOwnership: true
            )
        case .coordinator:
            return LeaguePermissions(
                operateWeek: true,
                appointCoordinators: false,
                editLeagueRules: false,
                changeScoringMode: false,
                changeRollingLock: true,
                removeMembers: false,
                deleteLeague: false,
                transferCommissioner: false,
                billingOrOwnership: false
            )
        case .member:
            return LeaguePermissions(
                operateWeek: false,
                appointCoordinators: false,
                editLeagueRules: false,
                changeScoringMode: false,
                changeRollingLock: false,
                removeMembers: false,
                deleteLeague: false,
                transferCommissioner: false,
                billingOrOwnership: false
            )
        }
    }
}

/// Client-side mirror of the rules matrix. Server rules are the real gate.
struct LeaguePermissions: Equatable, Sendable {
    var operateWeek: Bool
    var appointCoordinators: Bool
    var editLeagueRules: Bool
    var changeScoringMode: Bool
    var changeRollingLock: Bool
    var removeMembers: Bool
    var deleteLeague: Bool
    var transferCommissioner: Bool
    var billingOrOwnership: Bool
}

enum LeagueCoordinatorAssignmentError: LocalizedError, Equatable {
    case notAMember
    case isCommissioner

    var errorDescription: String? {
        switch self {
        case .notAMember:
            return "Coordinators have to be members of this league."
        case .isCommissioner:
            return "The commissioner can't also be a coordinator."
        }
    }
}

/// How a coordinator-map change is written. `unchanged` skips the field so other updates stay small.
enum CoordinatorMapWrite: Equatable, Sendable {
    case unchanged
    case deleteField
    case replace(oc: String?, dc: String?)
}

enum LeagueRolePolicy {
    static func role(of userId: String, in group: PickemGroup) -> LeagueActorRole {
        if userId == group.commissionerId { return .commissioner }
        let active = activeCoordinators(in: group)
        if let seat = active.role(for: userId) { return .coordinator(seat) }
        return .member
    }

    static func activeCoordinators(in group: PickemGroup) -> LeagueCoordinators {
        (group.coordinators ?? LeagueCoordinators()).normalized(
            memberIds: group.memberIds,
            commissionerId: group.commissionerId
        )
    }

    static func activeRole(of userId: String, in group: PickemGroup) -> LeagueCoordinatorRole? {
        if case .coordinator(let role) = role(of: userId, in: group) { return role }
        return nil
    }

    /// Appoint, replace, or clear one seat. Moving someone off the other seat keeps the two-person rule.
    static func assign(
        _ role: LeagueCoordinatorRole,
        userId: String?,
        group: PickemGroup
    ) throws -> LeagueCoordinators {
        var next = activeCoordinators(in: group)
        if let userId {
            guard group.memberIds.contains(userId) else { throw LeagueCoordinatorAssignmentError.notAMember }
            guard userId != group.commissionerId else { throw LeagueCoordinatorAssignmentError.isCommissioner }
            switch role {
            case .oc:
                if next.dc == userId { next.dc = nil }
                next.oc = userId
            case .dc:
                if next.oc == userId { next.oc = nil }
                next.dc = userId
            }
        } else {
            switch role {
            case .oc: next.oc = nil
            case .dc: next.dc = nil
            }
        }
        return next
    }

    static func clearing(_ userId: String, group: PickemGroup, commissionerId: String? = nil) -> LeagueCoordinators {
        let members = group.memberIds
        let commissioner = commissionerId ?? group.commissionerId
        return (group.coordinators ?? LeagueCoordinators())
            .clearing(userId)
            .normalized(memberIds: members, commissionerId: commissioner)
    }

    static func mapWrite(from current: LeagueCoordinators?, to next: LeagueCoordinators) -> CoordinatorMapWrite {
        let stored = current ?? LeagueCoordinators()
        if stored.oc == next.oc, stored.dc == next.dc {
            return .unchanged
        }
        if next.isEmpty { return .deleteField }
        return .replace(oc: next.oc, dc: next.dc)
    }

    /// Members the commissioner can put in `role`. The current holder is omitted; the other seat can move over.
    static func candidates(
        for role: LeagueCoordinatorRole,
        group: PickemGroup,
        members: [GroupMember]
    ) -> [GroupMember] {
        let active = activeCoordinators(in: group)
        let current = active.holder(of: role)
        return members
            .filter { member in
                group.memberIds.contains(member.id)
                    && member.id != group.commissionerId
                    && member.id != current
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}

extension PickemGroup {
    func coordinatorRole(for userId: String) -> LeagueCoordinatorRole? {
        LeagueRolePolicy.activeRole(of: userId, in: self)
    }
}
