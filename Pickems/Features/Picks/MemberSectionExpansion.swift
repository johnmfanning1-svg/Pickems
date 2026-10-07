import Foundation

/// Expand / collapse state for member cards in `GroupPicksView`.
///
/// The Selections and Pickems tabs share `GroupPicksView`. Cards start
/// collapsed only on the Selections tab while Selections are open (so a long
/// member list scans quickly); everywhere else they start expanded, as before.
/// Taps are stored as exceptions to the current default, and a change of
/// default (e.g. Selections close) starts fresh.
struct MemberSectionExpansion: Equatable {
    private var defaultCollapsed: Bool = false
    private var exceptions: Set<String> = []

    /// Selections tab (`forceNominatingDisplay`) during the active Selections phase.
    static func startsCollapsed(forceNominatingDisplay: Bool, weekStatus: WeekStatus?) -> Bool {
        forceNominatingDisplay && weekStatus == .selection
    }

    func isCollapsed(_ memberId: String, defaultCollapsed: Bool) -> Bool {
        guard defaultCollapsed == self.defaultCollapsed else { return defaultCollapsed }
        return exceptions.contains(memberId) ? !defaultCollapsed : defaultCollapsed
    }

    mutating func toggle(_ memberId: String, defaultCollapsed: Bool) {
        if defaultCollapsed != self.defaultCollapsed {
            self.defaultCollapsed = defaultCollapsed
            exceptions = []
        }
        if exceptions.contains(memberId) {
            exceptions.remove(memberId)
        } else {
            exceptions.insert(memberId)
        }
    }
}
