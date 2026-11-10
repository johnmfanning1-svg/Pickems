import Foundation

/// A row in the `publicLeagues` index. That collection is the only browse
/// source: private group documents, rosters, and picks are not readable here.
struct PublicLeagueListing: Codable, Identifiable, Equatable {
    var id: String { groupId }
    var groupId: String
    var name: String
    var inviteCode: String
    var memberCount: Int
    /// Omitted on the index. An explicit `false` is a private league and is not shown.
    var isPublic: Bool? = nil
}

/// What the search/join sheet's Browse path is allowed to show, and the invite
/// code it hands to the existing join flow.
enum PublicLeagueBrowse {
    static let indexCollection = "publicLeagues"
    static let entryTitle = "Browse"
    static let navigationTitle = "Browse"
    static let entrySubtitle = "Public leagues you can join without a code"
    static let entryFooter = "Private and invite-only leagues are not listed."
    static let accessibilityLabel = "Browse public leagues"
    static let accessibilityHint = "Shows public leagues you can join. Private leagues stay hidden."
    static let intro = "Public leagues anyone can join. Private and invite-only leagues stay hidden."
    static let emptyMessage = "No public leagues yet. A commissioner can make a league public when creating it, or later in league settings."

    /// Index rows a signed-in member can browse. No name or code is required to
    /// ask: this filters a list, it does not search `groups`.
    static func listings(from rows: [PublicLeagueListing]) -> [PublicLeagueListing] {
        let ranked = rows.sorted { lhs, rhs in
            if lhs.memberCount != rhs.memberCount {
                return lhs.memberCount > rhs.memberCount
            }
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.groupId < rhs.groupId
        }
        var seen = Set<String>()
        var kept: [PublicLeagueListing] = []
        for row in ranked {
            guard let listing = normalized(row) else { continue }
            guard seen.insert(listing.groupId).inserted else { continue }
            kept.append(listing)
        }
        return kept
    }

    static func isBrowsable(_ row: PublicLeagueListing) -> Bool {
        normalized(row) != nil
    }

    /// Invite code the search sheet would submit for this row. Nil when the row
    /// must not be listed or joined.
    static func joinCode(for row: PublicLeagueListing) -> String? {
        normalized(row)?.inviteCode
    }

    static func memberCountLabel(_ count: Int) -> String {
        let members = max(0, count)
        return members == 1 ? "1 member" : "\(members) members"
    }

    static func actionTitle(alreadyMember: Bool) -> String {
        alreadyMember ? "Open" : "Join"
    }

    static func actionHint(alreadyMember: Bool) -> String {
        alreadyMember ? "Open this league" : "Join this public league"
    }

    static func rowLabel(name: String, memberCount: Int, alreadyMember: Bool) -> String {
        "\(name), \(memberCountLabel(memberCount)), \(actionTitle(alreadyMember: alreadyMember))"
    }

    private static func normalized(_ row: PublicLeagueListing) -> PublicLeagueListing? {
        if row.isPublic == false { return nil }
        let groupId = row.groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupId.isEmpty, !name.isEmpty, row.memberCount >= 0 else { return nil }
        let code = InviteCodeRules.normalize(row.inviteCode)
        guard InviteCodeRules.isValidFormat(code) else { return nil }
        var listing = row
        listing.groupId = groupId
        listing.name = name
        listing.inviteCode = code
        return listing
    }
}
