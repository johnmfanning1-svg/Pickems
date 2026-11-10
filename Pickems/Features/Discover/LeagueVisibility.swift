import Foundation

/// Public or private when a commissioner creates a league.
///
/// Private is the default. A public league is listed in Browse only after the
/// group document is committed with `isPublic == true`: `firestore.rules`
/// (`leagueIsDiscoverable` + `publicLeagueIndexOk`) reads that document and
/// rejects the index row otherwise. The commissioner must be the writer.
nonisolated enum LeagueVisibility: String, CaseIterable, Identifiable, Equatable {
    case privateLeague
    case publicLeague

    var id: String { rawValue }

    static let createDefault: LeagueVisibility = .privateLeague

    var isPublic: Bool { self == .publicLeague }

    var title: String {
        switch self {
        case .privateLeague: "Private"
        case .publicLeague: "Public"
        }
    }

    var detail: String {
        switch self {
        case .privateLeague: "Invite-only. Stays off Browse."
        case .publicLeague: "Appears in Browse. Anyone can join."
        }
    }

    var reviewLabel: String {
        switch self {
        case .privateLeague: "Private · invite-only"
        case .publicLeague: "Public · listed in Browse"
        }
    }

    static let sectionTitle = "Visibility"
    static let sectionDetail = "Public leagues appear in Browse and anyone can join. Private stays invite-only."

    static let settingsToggleTitle = "List in Browse"
    static let publicSettingsFooter = "Public leagues appear in Browse. Anyone signed in can join. See who's in is on the Pickems tab."
    static let privateSettingsFooter = "Private leagues stay invite-only and off Browse. Turn on Only commissioner can invite to hide Invite Friends for members — they will be asked to contact you instead. You still share the code from Invite Friends on the Leagues tab."

    /// Shown on the invite step when the group doc was created but Browse has no row.
    static let listingFailedNotice = "Your league was created, but it isn't in Browse yet. In Commissioner Settings, leave List in Browse on and save to try again."
    /// Shown when the row would be rejected by `publicLeagueIndexOk` (name or invite code).
    static let listingRejectedNotice = "Your league was created, but Browse couldn't list it. Names in Browse must be 80 characters or fewer, with a 4–8 character invite code. Fix that in Commissioner Settings and save."

    /// `publicLeagueIndexOk` allows a name of at most this many characters.
    static let maxIndexNameLength = 80

    /// Keys `publicLeagueIndexOk` allows. `updatedAt` is optional in rules;
    /// creation and Commissioner Settings both write it.
    static let indexFieldNames: Set<String> = ["groupId", "name", "inviteCode", "memberCount", "updatedAt"]

    nonisolated struct IndexRow: Equatable {
        var groupId: String
        var name: String
        var inviteCode: String
        var memberCount: Int

        /// Index fields other than the server timestamp the writer adds.
        func storedFields() -> [String: Any] {
            [
                "groupId": groupId,
                "name": name,
                "inviteCode": inviteCode,
                "memberCount": memberCount,
            ]
        }
    }

    nonisolated enum CreateWriteStep: Equatable {
        case groupDocument
        case inviteCode
        case commissionerMember
        case publicIndex
    }

    /// Group document first, index last, and only when the league is public.
    /// Rules `get()` the group doc, so the index write cannot precede it.
    /// A failed member write therefore never publishes a half-created league.
    static func createWriteOrder(isPublic: Bool) -> [CreateWriteStep] {
        var steps: [CreateWriteStep] = [.groupDocument, .inviteCode, .commissionerMember]
        if isPublic {
            steps.append(.publicIndex)
        }
        return steps
    }

    /// Nil when `publicLeagueIndexOk` would deny the row. Trims the name and
    /// normalizes the invite code so the written document matches the rules.
    static func indexRow(
        groupId: String,
        name: String,
        inviteCode: String,
        memberCount: Int
    ) -> IndexRow? {
        let id = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = InviteCodeRules.normalize(inviteCode)
        guard !id.isEmpty,
              !trimmedName.isEmpty,
              trimmedName.count <= maxIndexNameLength,
              InviteCodeRules.isValidFormat(code),
              memberCount >= 0 else { return nil }
        return IndexRow(groupId: id, name: trimmedName, inviteCode: code, memberCount: memberCount)
    }

    static func createdSubtitle(isPublic: Bool) -> String {
        isPublic
            ? "Anyone can join from Browse. You can still share the invite code."
            : "Share your invite code so friends can join."
    }

    /// Notice for the invite step. Nil means creation finished with nothing to warn about.
    /// A private league never lists, so a publish error is ignored.
    static func browseListingNotice(
        isPublic: Bool,
        indexRow: IndexRow?,
        publishError: Error?
    ) -> String? {
        guard isPublic else { return nil }
        guard indexRow != nil else { return listingRejectedNotice }
        guard publishError == nil else { return listingFailedNotice }
        return nil
    }
}

struct LeagueCreateResult: Equatable {
    var group: PickemGroup
    /// Set when the league exists but Browse does not list it yet.
    var browseListingNotice: String?
}

/// Writes the Browse index. A miss is returned, never thrown, so league creation still succeeds.
///
/// Both attempts run, including after a permission denial. Rules read the group
/// document to decide if the league is discoverable, so the first attempt can
/// fail before that write is visible and the second can succeed.
nonisolated enum PublicLeagueIndexPublish {
    static let maxAttempts = 2

    /// The last error after `maxAttempts`, or nil when a write succeeded.
    /// The write runs on the main actor because it touches Firestore from `GroupService`.
    static func attempt(_ write: @MainActor () async throws -> Void) async -> Error? {
        var lastError: Error?
        for _ in 1...maxAttempts {
            do {
                try await write()
                return nil
            } catch {
                lastError = error
            }
        }
        return lastError
    }
}
