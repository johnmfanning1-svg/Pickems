import Foundation
import Security
import FirebaseFirestore
import FirebaseAuth

@MainActor
@Observable
final class GroupService {
    var groups: [PickemGroup] = []
    var selectedGroup: PickemGroup?
    var members: [GroupMember] = []
    var standings: GroupStandings?
    var currentWeek: WeekSummary?
    /// Weeks available for the selected group (Picks tab week bar). Ascending by season/week.
    var availableWeeks: [WeekSummary] = []
    var seasonDateRangeByWeekId: [String: String] = [:]
    var cfbWeek: CFBWeekInfo?
    var seasonArchives: [SeasonArchive] = []
    var careerRecords: [CareerRecord] = []
    var isLoading = false
    var isClosingSeason = false
    var errorMessage: String?
    /// First `loadGroups` snapshot has arrived (even if empty). Gates onboarding vs main.
    var hasCompletedInitialGroupLoad = false

    /// Lazy so constructing `AppState` cannot touch Firestore before Firebase configure.
    @ObservationIgnored
    @ObservationIgnored private lazy var db = Firestore.firestore()
    @ObservationIgnored
    private var groupListener: ListenerRegistration?
    @ObservationIgnored
    private var weekListener: ListenerRegistration?
    @ObservationIgnored
    private var standingsListener: ListenerRegistration?
    @ObservationIgnored
    private var seasonsListener: ListenerRegistration?
    @ObservationIgnored
    private var careerListener: ListenerRegistration?
    @ObservationIgnored
    private var observedWeekId: String?
    @ObservationIgnored
    private var observedGroupId: String?
    /// When true, Picks is browsing a non-active week — don't snap back to ESPN current on sync.
    @ObservationIgnored
    private var weekSelectionPinned = false
    /// Deep-link league id waiting for `loadGroups` to finish.
    @ObservationIgnored
    private var pendingGroupId: String?

    func loadGroups(for userId: String) {
        groupListener?.remove()
        hasCompletedInitialGroupLoad = false
        AppLog.info(AppLog.firestore, "loadGroups listener attached", metadata: [
            "uid": AppEvents.shortUID(userId),
        ])
        groupListener = db.collection("groups")
            .whereField("memberIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.hasCompletedInitialGroupLoad = true
                        UserFacingError.apply(error, to: &self.errorMessage, context: .listener)
                        AppEvents.failure(.groupsListenerError, error: error, metadata: [
                            "uid": AppEvents.shortUID(userId),
                        ])
                        return
                    }
                    var dropped = 0
                    self.groups = snapshot?.documents.compactMap { doc in
                        do {
                            return try doc.data(as: PickemGroup.self)
                        } catch {
                            dropped += 1
                            AppEvents.track(.groupsDecodeDropped, metadata: [
                                "doc_id": doc.documentID,
                                "error": AppLog.describe(error),
                            ])
                            return nil
                        }
                    } ?? []
                    if dropped > 0 {
                        AppLog.notice(AppLog.firestore, "dropped undecodable group docs", metadata: [
                            "count": "\(dropped)",
                            "kept": "\(self.groups.count)",
                        ])
                    }
                    self.hasCompletedInitialGroupLoad = true
                    Task { @MainActor in
                        await self.backfillInviteCodeIndexes(for: userId)
                    }
                    let previousSelectedId = self.selectedGroup?.id
                    if let pendingId = self.pendingGroupId,
                       let pending = self.groups.first(where: { $0.id == pendingId }) {
                        self.pendingGroupId = nil
                        self.selectedGroup = pending
                    } else if let selected = self.selectedGroup,
                       !self.groups.contains(where: { $0.id == selected.id }) {
                        self.selectedGroup = self.groups.first
                        self.clearWeekObservationIfNeeded()
                    } else if self.selectedGroup == nil {
                        self.selectedGroup = self.groups.first
                    }
                    if let groupId = self.selectedGroup?.id {
                        // Avoid re-entrant ESPN/week observe on every membership metadata tick.
                        let selectionChanged = previousSelectedId != groupId
                        if selectionChanged || self.observedGroupId != groupId || self.currentWeek == nil {
                            await self.syncCurrentWeekFromESPN(groupId: groupId)
                        }
                    } else {
                        self.clearWeekObservationIfNeeded()
                    }
                    CrashReport.setValue("\(self.groups.count)", forKey: "group_count")
                }
            }
    }

    func selectGroup(_ group: PickemGroup) {
        pendingGroupId = nil
        selectedGroup = group
        weekSelectionPinned = false
        availableWeeks = []
        seasonDateRangeByWeekId = [:]
        Task {
            await syncCurrentWeekFromESPN(groupId: group.id)
            await loadAvailableWeeks(groupId: group.id)
        }
    }

    /// Select by id (push / deep link). If the league is not loaded yet, remember it.
    func selectGroup(id: String) {
        if let group = groups.first(where: { $0.id == id }) {
            selectGroup(group)
        } else {
            pendingGroupId = id
        }
    }

    /// True when `week` is after the calendar's current Pickems week (e.g. W1 during Week 0).
    func isFutureWeek(_ week: WeekSummary) -> Bool {
        guard let cfb = cfbWeek else { return false }
        let active = CFBWeekCalendar.resolve(espn: cfb)
        if week.seasonYear != active.seasonYear {
            return week.seasonYear > active.seasonYear
        }
        return week.weekNumber > active.weekNumber
    }

    /// Drop a pinned browse immediately so Selections/Pickems don't paint the old week for a frame.
    func unpinToActiveWeekLocally() {
        weekSelectionPinned = false
        guard let activeId = cfbWeek.map({ CFBWeekSync.weekId(for: $0) }) else { return }
        if let known = availableWeeks.first(where: { $0.id == activeId }), currentWeek?.id != known.id {
            currentWeek = known
        }
        guard let groupId = selectedGroup?.id else { return }
        observeGroupDetails(groupId: groupId, weekId: activeId)
    }

    /// Unpin any browsed week and re-attach to the calendar's current week.
    func jumpToActiveWeek() async {
        unpinToActiveWeekLocally()
        guard let groupId = selectedGroup?.id else { return }
        await syncCurrentWeekFromESPN(groupId: groupId)
    }

    func dateRangeLabel(for weekId: String) -> String? {
        seasonDateRangeByWeekId[weekId]
    }

    /// Switch the observed week for the selected group (Picks week tabs). Defaults stay on the active ESPN week.
    func selectWeek(weekId: String) async {
        guard let groupId = selectedGroup?.id else { return }
        let activeWeekId = cfbWeek.map { CFBWeekSync.weekId(for: $0) }
        weekSelectionPinned = activeWeekId.map { $0 != weekId } ?? (observedWeekId != weekId)
        // Seed immediately so Picks/pick listeners don't briefly attach to the previous week.
        if let known = availableWeeks.first(where: { $0.id == weekId }) {
            currentWeek = known
        }
        // Attach the new week observer before any await. Leaving the previous week's
        // listener live during `ensureWeekDocumentExists` lets a stale snapshot
        // overwrite `currentWeek` (Week 1 → Week 0 "Slate is set" → Week 1).
        if !(observedGroupId == groupId && observedWeekId == weekId && weekListener != nil) {
            observeGroupDetails(groupId: groupId, weekId: weekId)
        }
        let rules = selectedGroup?.rules ?? .default
        await ensureWeekDocumentExists(
            groupId: groupId,
            weekId: weekId,
            info: weekInfo(forWeekId: weekId),
            rules: rules
        )
    }

    /// Loads weeks for the horizontal Picks tab bar, filling future ESPN weeks that are not minted yet.
    func loadAvailableWeeks(groupId: String) async {
        do {
            var weeks = try await fetchPastWeeks(groupId: groupId, limit: 20)
            if let current = currentWeek, !weeks.contains(where: { $0.id == current.id }) {
                weeks.append(current)
            }
            let year = currentWeek?.seasonYear
                ?? cfbWeek?.seasonYear
                ?? CFBSeasonCalendar.seasonYear()
            let calendarWeeks = await ESPNService.shared.seasonWeeks(year: year)
            seasonDateRangeByWeekId = Dictionary(
                uniqueKeysWithValues: calendarWeeks.map { ($0.id, $0.dateRangeLabel) }
            )
            let rules = selectedGroup?.rules ?? .default
            let memberCount = max(selectedGroup?.memberIds.count ?? members.count, 1)
            var byId = Dictionary(uniqueKeysWithValues: weeks.map { ($0.id, $0) })
            for slot in calendarWeeks where byId[slot.id] == nil {
                byId[slot.id] = CFBWeekSync.makeWeekSummary(
                    id: slot.id,
                    info: CFBWeekInfo(
                        seasonYear: slot.seasonYear,
                        weekNumber: slot.espnWeekNumber,
                        seasonType: cfbWeek?.seasonType ?? 2,
                        label: slot.dateRangeLabel
                    ),
                    rules: rules,
                    memberCount: memberCount
                )
            }
            availableWeeks = Self.sortedWeeksAscending(Array(byId.values))
        } catch {
            if let current = currentWeek {
                availableWeeks = [current]
            } else {
                availableWeeks = []
            }
        }
    }

    func syncCurrentWeekFromESPN(groupId: String) async {
        let rules = selectedGroup?.rules ?? .default
        let weekInfo: CFBWeekInfo
        do {
            weekInfo = try await ESPNService.shared.currentWeek()
        } catch {
            UserFacingError.apply(error, to: &errorMessage)
            if observedWeekId == nil {
                observeGroupDetails(groupId: groupId, weekId: CFBWeekSync.fallbackWeekId())
            }
            return
        }

        cfbWeek = weekInfo
        let weekId = await resolvedWeekIdToObserve(groupId: groupId, espn: weekInfo)

        // Already listening to this week — never remount (remounts clear/jitter Home).
        if observedGroupId == groupId, observedWeekId == weekId {
            await ensureWeekDocumentExists(groupId: groupId, weekId: weekId, info: weekInfo, rules: rules)
            return
        }

        // Picks tab may be browsing a past week — keep that observation; still seed the active week doc.
        if weekSelectionPinned, observedGroupId == groupId, observedWeekId != nil {
            await ensureWeekDocumentExists(groupId: groupId, weekId: weekId, info: weekInfo, rules: rules)
            return
        }

        isLoading = currentWeek == nil
        defer { isLoading = false }

        await ensureWeekDocumentExists(groupId: groupId, weekId: weekId, info: weekInfo, rules: rules)
        observeGroupDetails(groupId: groupId, weekId: weekId)
    }

    /// Week 0 is minted for new/empty groups. In-progress 2026-W1 groups stay on W1 until
    /// the admin migration creates 2026-W0 so every member flips together.
    private func resolvedWeekIdToObserve(groupId: String, espn: CFBWeekInfo) async -> String {
        let app = CFBWeekCalendar.resolve(espn: espn)
        guard app.weekNumber == 0 else { return app.id }

        let weeks = db.collection("groups").document(groupId).collection("weeks")
        if let w0 = try? await weeks.document(app.id).getDocument(), w0.exists {
            return app.id
        }

        let w1Id = "\(app.seasonYear)-W1"
        if let w1 = try? await weeks.document(w1Id).getDocument(), w1.exists,
           weekDocumentHasUserActivity(w1) {
            return w1Id
        }
        return app.id
    }

    private func weekDocumentHasUserActivity(_ snapshot: DocumentSnapshot) -> Bool {
        guard let week = try? snapshot.data(as: WeekSummary.self) else { return false }
        if week.nominationCount > 0 { return true }
        if week.status != .selection { return true }
        if week.selectionDeadline != nil { return true }
        if week.pickDeadline != nil { return true }
        if week.lockedAt != nil { return true }
        return false
    }

    private func weekInfo(forWeekId weekId: String) -> CFBWeekInfo {
        let parsed = CFBWeekSync.parseWeekId(weekId)
        let year = parsed?.seasonYear ?? cfbWeek?.seasonYear ?? CFBSeasonCalendar.seasonYear()
        let appWeek = parsed?.weekNumber ?? 0
        return CFBWeekInfo(
            seasonYear: year,
            weekNumber: CFBWeekCalendar.espnScoreboardWeek(appWeek),
            seasonType: cfbWeek?.seasonType ?? 2,
            label: "Season \(year) | Week \(appWeek)"
        )
    }

    private static func sortedWeeksAscending(_ weeks: [WeekSummary]) -> [WeekSummary] {
        weeks.sorted {
            if $0.seasonYear != $1.seasonYear { return $0.seasonYear < $1.seasonYear }
            return $0.weekNumber < $1.weekNumber
        }
    }

    private func ensureWeekDocumentExists(
        groupId: String,
        weekId: String,
        info: CFBWeekInfo,
        rules: GroupRules
    ) async {
        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
        do {
            let snapshot = try await weekRef.getDocument()
            if !snapshot.exists {
                let memberCount = selectedGroup?.id == groupId
                    ? max(selectedGroup?.memberIds.count ?? members.count, 1)
                    : max(members.count, 1)
                let week = CFBWeekSync.makeWeekSummary(
                    id: weekId,
                    info: info,
                    rules: rules,
                    memberCount: memberCount
                )
                try await weekRef.setData(from: week)
                // Seed local state immediately so Home doesn't flash an empty week card.
                publishCurrentWeekIfUnpinned(week)
                await seedFixedSlateIfNeeded(groupId: groupId, weekId: weekId, week: week)
            } else {
                let existing = try? snapshot.data(as: WeekSummary.self)
                if let existing {
                    publishCurrentWeekIfUnpinned(existing)
                    await seedFixedSlateIfNeeded(groupId: groupId, weekId: weekId, week: existing)
                }
                await reconcileSelectionWeekSnapshot(groupId: groupId, rules: rules)
            }
        } catch {
            UserFacingError.apply(error, to: &errorMessage)
        }
    }

    /// Keep a pinned Picks/Selections week (including future W1 during Week 0) from
    /// being overwritten when we seed the calendar's active week document.
    private func publishCurrentWeekIfUnpinned(_ week: WeekSummary) {
        if weekSelectionPinned, let current = currentWeek, current.id != week.id {
            return
        }
        if currentWeek?.id != week.id {
            currentWeek = week
        }
    }

    /// Writes ESPN's Saturday openers onto a fixed-slate Week 0. Idempotent merge.
    private func seedFixedSlateIfNeeded(groupId: String, weekId: String, week: WeekSummary) async {
        guard week.skipsSelection else { return }
        do {
            let games = try await ESPNService.shared.fetchScoreboard(for: week)
            guard !games.isEmpty else { return }
            let weekRef = db.collection("groups").document(groupId)
                .collection("weeks").document(weekId)
            let gamesRef = weekRef.collection("games")
            let existingSnap = try await gamesRef.getDocuments()
            let existingIds = Set(existingSnap.documents.map(\.documentID))
            var kickoffs: [Date] = existingSnap.documents.compactMap { doc in
                SlateGame.fromDocument(id: doc.documentID, data: doc.data())?.kickoff
            }
            for game in games {
                let slate = game.toSlateGame()
                if !existingIds.contains(slate.espnEventId) {
                    try await gamesRef.document(slate.espnEventId).setData(from: slate)
                }
                kickoffs.append(slate.kickoff)
            }
            var updates: [String: Any] = [
                "slateSize": games.count,
                "slateSource": CFBWeekCalendar.weekZeroSlateSource,
            ]
            if week.status == .selection {
                updates["status"] = WeekStatus.picking.rawValue
            }
            if week.pickDeadline == nil, let deadline = kickoffs.min() {
                updates["pickDeadline"] = Timestamp(date: deadline)
            }
            if week.lockedAt == nil {
                updates["lockedAt"] = Timestamp(date: Date())
            }
            try await weekRef.updateData(updates)
            if currentWeek?.id == weekId {
                currentWeek?.slateSize = games.count
                currentWeek?.slateSource = CFBWeekCalendar.weekZeroSlateSource
                if week.status == .selection {
                    currentWeek?.status = .picking
                }
                if currentWeek?.pickDeadline == nil {
                    currentWeek?.pickDeadline = kickoffs.min()
                }
                if currentWeek?.lockedAt == nil {
                    currentWeek?.lockedAt = Date()
                }
            }
        } catch {
            AppLog.error(AppLog.network, "week 0 slate seed failed", error: error)
        }
    }

    /// Commissioner sets the nomination deadline for the current selection week.
    func setSelectionDeadline(
        groupId: String,
        weekId: String,
        deadline: Date,
        setByUserId: String
    ) async throws {
        let updates: [String: Any] = [
            "selectionDeadline": Timestamp(date: deadline),
            "selectionDeadlineSetAt": Timestamp(date: Date()),
            "selectionDeadlineSetBy": setByUserId,
        ]
        try await db.week(groupId: groupId, weekId: weekId).updateData(updates)
        if var week = currentWeek, week.id == weekId {
            week.selectionDeadline = deadline
            week.selectionDeadlineSetAt = Date()
            week.selectionDeadlineSetBy = setByUserId
            currentWeek = week
        }
    }

    /// Commissioner sets or extends the spread-pick deadline for the current week.
    func setPickDeadline(
        groupId: String,
        weekId: String,
        deadline: Date
    ) async throws {
        try await db.week(groupId: groupId, weekId: weekId).updateData([
            "pickDeadline": Timestamp(date: deadline),
        ])
        if var week = currentWeek, week.id == weekId {
            week.pickDeadline = deadline
            currentWeek = week
        }
        if let idx = availableWeeks.firstIndex(where: { $0.id == weekId }) {
            availableWeeks[idx].pickDeadline = deadline
        }
    }

    /// Commissioner returns the week to `.selection` so members can remake Selections.
    func reopenWeekForSelections(groupId: String, weekId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) ?? selectedGroup,
              group.id == groupId else {
            throw GroupError.groupNotFound
        }
        guard group.commissionerId == Auth.auth().currentUser?.uid else {
            throw GroupError.notCommissioner
        }

        try await db.week(groupId: groupId, weekId: weekId).updateData(
            WeekTransition.toSelectionUpdates()
        )
        // Drop a passed (or any) Selection deadline so `canRemakeSelections` and
        // nomination rules open again, and reset the CF bookkeeping flag so a
        // newly set deadline can auto-open Pickems later.
        try await db.week(groupId: groupId, weekId: weekId).updateData([
            "selectionDeadline": FieldValue.delete(),
            "selectionDeadlineSetAt": FieldValue.delete(),
            "selectionDeadlineSetBy": FieldValue.delete(),
            "selectionDeadlinePassedNotified": FieldValue.delete(),
        ])
        if var week = currentWeek, week.id == weekId {
            week.status = .selection
            week.lockedAt = nil
            week.selectionDeadline = nil
            week.selectionDeadlineSetAt = nil
            week.selectionDeadlineSetBy = nil
            currentWeek = week
        }
        if let idx = availableWeeks.firstIndex(where: { $0.id == weekId }) {
            availableWeeks[idx].status = .selection
            availableWeeks[idx].lockedAt = nil
            availableWeeks[idx].selectionDeadline = nil
            availableWeeks[idx].selectionDeadlineSetAt = nil
            availableWeeks[idx].selectionDeadlineSetBy = nil
        }
    }

    /// Commissioner reopens a locked week for picking with a new deadline.
    func reopenWeekForPicking(
        groupId: String,
        weekId: String,
        deadline: Date
    ) async throws {
        try await db.week(groupId: groupId, weekId: weekId).updateData([
            "status": WeekStatus.picking.rawValue,
            "pickDeadline": Timestamp(date: deadline),
            "lockedAt": FieldValue.delete(),
        ])
        if var week = currentWeek, week.id == weekId {
            week.status = .picking
            week.pickDeadline = deadline
            week.lockedAt = nil
            currentWeek = week
        }
        if let idx = availableWeeks.firstIndex(where: { $0.id == weekId }) {
            availableWeeks[idx].status = .picking
            availableWeeks[idx].pickDeadline = deadline
            availableWeeks[idx].lockedAt = nil
        }
    }

    func createGroup(
        name: String,
        commissionerId: String,
        displayName: String,
        avatarColorHex: String? = nil,
        avatarImageURL: String? = nil
    ) async throws -> PickemGroup {
        AppEvents.track(.onboardingCreateStarted, metadata: [
            "uid": AppEvents.shortUID(commissionerId),
        ])
        do {
            let inviteCode = generateInviteCode()
            let groupRef = db.collection("groups").document()
            let group = PickemGroup(
                id: groupRef.documentID,
                name: name,
                inviteCode: inviteCode,
                commissionerId: commissionerId,
                memberIds: [commissionerId],
                rules: .default,
                createdAt: Date()
            )
            try await groupRef.setData(from: group)
            try await db.collection("inviteCodes").document(inviteCode).setData(["groupId": groupRef.documentID])

            let member = GroupMember(
                id: commissionerId,
                displayName: displayName,
                avatarColorHex: avatarColorHex ?? AvatarColors.randomHex(),
                role: .commissioner,
                joinedAt: Date(),
                seasonWins: 0,
                seasonLosses: 0,
                avatarImageURL: avatarImageURL
            )
            try await groupRef.collection("members").document(commissionerId).setData(from: member)
            selectedGroup = group
            if !groups.contains(where: { $0.id == group.id }) {
                groups.append(group)
            }
            await syncCurrentWeekFromESPN(groupId: group.id)
            AppEvents.track(.onboardingCreateSucceeded, metadata: [
                "uid": AppEvents.shortUID(commissionerId),
                "group_id": group.id,
            ])
            return group
        } catch {
            AppEvents.failure(.onboardingCreateFailed, error: error, metadata: [
                "uid": AppEvents.shortUID(commissionerId),
            ])
            throw error
        }
    }

    func joinGroup(
        inviteCode: String,
        userId: String,
        displayName: String,
        avatarColorHex: String,
        avatarImageURL: String? = nil
    ) async throws {
        let normalizedCode = inviteCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let codeDoc = try await db.collection("inviteCodes").document(normalizedCode).getDocument()
        guard codeDoc.exists, let groupId = codeDoc.data()?["groupId"] as? String else {
            throw GroupError.invalidInviteCode
        }

        let doc = try await db.collection("groups").document(groupId).getDocument()
        guard doc.exists else {
            throw GroupError.invalidInviteCode
        }

        var group = try doc.data(as: PickemGroup.self)
        guard !group.memberIds.contains(userId) else {
            selectedGroup = group
            await syncCurrentWeekFromESPN(groupId: group.id)
            return
        }

        try await doc.reference.updateData(["memberIds": FieldValue.arrayUnion([userId])])
        if !group.memberIds.contains(userId) {
            group.memberIds.append(userId)
        }

        let member = GroupMember(
            id: userId,
            displayName: displayName,
            avatarColorHex: avatarColorHex,
            role: .member,
            joinedAt: Date(),
            seasonWins: 0,
            seasonLosses: 0,
            avatarImageURL: avatarImageURL
        )
        try await doc.reference.collection("members").document(userId).setData(from: member)
        selectedGroup = group
        await syncCurrentWeekFromESPN(groupId: group.id)
        await reconcileSelectionWeekSnapshot(groupId: group.id, rules: group.rules)
    }

    /// Keeps league member rows in sync when a user changes their unique display name.
    func syncMemberDisplayName(userId: String, displayName: String) async {
        await syncMemberProfileFields(userId: userId, fields: ["displayName": displayName])
    }

    /// Mirrors profile photo onto every league membership doc.
    func syncMemberAvatarURL(userId: String, avatarImageURL: String?) async {
        let fields: [String: Any]
        if let avatarImageURL, !avatarImageURL.isEmpty {
            fields = ["avatarImageURL": avatarImageURL]
        } else {
            fields = ["avatarImageURL": FieldValue.delete()]
        }
        await syncMemberProfileFields(userId: userId, fields: fields)
    }

    private func syncMemberProfileFields(userId: String, fields: [String: Any]) async {
        for group in groups {
            let ref = db.collection("groups").document(group.id)
                .collection("members").document(userId)
            do {
                try await ref.updateData(fields)
                if let idx = members.firstIndex(where: { $0.id == userId }),
                   selectedGroup?.id == group.id {
                    if let name = fields["displayName"] as? String {
                        members[idx].displayName = name
                    }
                    if fields.keys.contains("avatarImageURL") {
                        members[idx].avatarImageURL = fields["avatarImageURL"] as? String
                    }
                }
            } catch {
                AppLog.error(AppLog.firestore, "member profile sync failed", error: error, metadata: [
                    "group_id": group.id,
                    "uid": AppEvents.shortUID(userId),
                ])
            }
        }
    }

    func leaveGroup(groupId: String, userId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) else {
            throw GroupError.groupNotFound
        }
        guard group.memberIds.contains(userId) else { return }

        // Commissioners must transfer the role first (or delete if they are alone).
        if group.commissionerId == userId {
            if group.memberIds.count == 1 {
                try await deleteGroup(groupId: groupId)
                return
            }
            throw GroupError.cannotLeaveAsSoleCommissioner
        }

        try await removeMemberFromGroup(group: group, userId: userId)
    }

    /// Leaves or dissolves every league so account deletion can finish.
    /// Sole-member leagues are deleted; multi-member commissioner leagues auto-transfer first.
    func leaveAllGroupsForAccountDeletion(userId: String) async throws {
        let owned = groups.filter { $0.memberIds.contains(userId) }
        for group in owned {
            try await leaveGroupForAccountDeletion(groupId: group.id, userId: userId)
        }
    }

    private func leaveGroupForAccountDeletion(groupId: String, userId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) else { return }
        guard group.memberIds.contains(userId) else { return }

        if group.commissionerId == userId {
            if group.memberIds.count == 1 {
                try await deleteGroup(groupId: groupId)
                return
            }
            guard let successor = group.memberIds.first(where: { $0 != userId }) else {
                try await deleteGroup(groupId: groupId)
                return
            }
            try await transferCommissioner(groupId: groupId, toUserId: successor)
        }

        guard let updated = groups.first(where: { $0.id == groupId }) else { return }
        try await removeMemberFromGroup(group: updated, userId: userId)
    }

    private func removeMemberFromGroup(group: PickemGroup, userId: String) async throws {
        let groupId = group.id
        let updatedIds = group.memberIds.filter { $0 != userId }
        try await db.collection("groups").document(groupId).updateData(["memberIds": updatedIds])
        try await db.collection("groups").document(groupId)
            .collection("members").document(userId).delete()

        groups.removeAll { $0.id == groupId }
        if selectedGroup?.id == groupId {
            selectedGroup = groups.first
            if let next = selectedGroup {
                await syncCurrentWeekFromESPN(groupId: next.id)
            } else {
                clearWeekObservationIfNeeded()
                seasonArchives = []
                careerRecords = []
            }
        }
        if group.isPublic {
            try? await db.collection("publicLeagues").document(groupId)
                .updateData(["memberCount": updatedIds.count])
        }
    }

    func deleteGroup(groupId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) else {
            throw GroupError.groupNotFound
        }
        guard group.commissionerId == Auth.auth().currentUser?.uid else {
            throw GroupError.notCommissioner
        }

        let groupRef = db.collection("groups").document(groupId)
        let weeks = try await groupRef.collection("weeks").getDocuments()
        for week in weeks.documents {
            try await deleteWeekData(groupRef: groupRef, weekId: week.documentID)
        }
        let members = try await groupRef.collection("members").getDocuments()
        for member in members.documents {
            try await member.reference.delete()
        }
        let seasons = try await groupRef.collection("seasons").getDocuments()
        for season in seasons.documents {
            try await season.reference.delete()
        }
        let careers = try await groupRef.collection("career").getDocuments()
        for career in careers.documents {
            try await career.reference.delete()
        }
        try await groupRef.collection("standings").document("current").delete()
        try await db.collection("inviteCodes").document(group.inviteCode).delete()
        try? await db.collection("publicLeagues").document(groupId).delete()
        try await groupRef.delete()

        groups.removeAll { $0.id == groupId }
        if selectedGroup?.id == groupId {
            selectedGroup = groups.first
            if selectedGroup == nil {
                clearWeekObservationIfNeeded()
                seasonArchives = []
                careerRecords = []
            } else if let next = selectedGroup {
                await syncCurrentWeekFromESPN(groupId: next.id)
            }
        }
    }

    /// Clears listeners and membership state on sign-out.
    func resetSession() {
        groupListener?.remove()
        groupListener = nil
        seasonsListener?.remove()
        careerListener?.remove()
        seasonsListener = nil
        careerListener = nil
        clearWeekObservationIfNeeded()
        groups = []
        selectedGroup = nil
        pendingGroupId = nil
        seasonArchives = []
        careerRecords = []
        hasCompletedInitialGroupLoad = false
        errorMessage = nil
    }

    /// Transfers commissioner role to another member. Only one commissioner at a time.
    func transferCommissioner(groupId: String, toUserId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) else {
            throw GroupError.groupNotFound
        }
        guard let currentUid = Auth.auth().currentUser?.uid,
              group.commissionerId == currentUid else {
            throw GroupError.notCommissioner
        }
        guard toUserId != group.commissionerId else { return }
        guard group.memberIds.contains(toUserId) else {
            throw GroupError.groupNotFound
        }

        let previousCommissionerId = group.commissionerId

        try await db.collection("groups").document(groupId).updateData(["commissionerId": toUserId])
        try await db.collection("groups").document(groupId)
            .collection("members").document(toUserId)
            .updateData(["role": GroupMember.MemberRole.commissioner.rawValue])
        try await db.collection("groups").document(groupId)
            .collection("members").document(previousCommissionerId)
            .updateData(["role": GroupMember.MemberRole.member.rawValue])

        if var group = groups.first(where: { $0.id == groupId }) {
            group.commissionerId = toUserId
            if let idx = groups.firstIndex(where: { $0.id == groupId }) {
                groups[idx] = group
            }
            if selectedGroup?.id == groupId {
                selectedGroup = group
            }
        }
        if let idx = members.firstIndex(where: { $0.id == toUserId }) {
            members[idx].role = .commissioner
        }
        if let idx = members.firstIndex(where: { $0.id == previousCommissionerId }) {
            members[idx].role = .member
        }
    }

    func fetchPastWeeks(groupId: String, limit: Int = 16) async throws -> [WeekSummary] {
        let snapshot = try await db.collection("groups").document(groupId)
            .collection("weeks")
            .order(by: "weekNumber", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: WeekSummary.self) }
    }

    func loadPlayerSeasonStats(groupId: String, userId: String) async throws -> PlayerSeasonStats {
        let weeks = try await fetchPastWeeks(groupId: groupId, limit: 20)
        var weeklyRecords: [WeeklyRecord] = []
        var seasonWins = 0
        var seasonLosses = 0
        var bestWeek: WeeklyRecord?

        for week in weeks where week.status == .scored {
            let pickSnap = try await db.collection("groups").document(groupId)
                .collection("weeks").document(week.id)
                .collection("picks").document(userId).getDocument()
            let gamesSnap = try await db.collection("groups").document(groupId)
                .collection("weeks").document(week.id)
                .collection("games").getDocuments()
            let games = gamesSnap.documents.compactMap { doc in
                SlateGame.fromDocument(id: doc.documentID, data: doc.data())
            }
            guard let pick = try? pickSnap.data(as: UserPick.self) else { continue }

            var wins = 0
            var losses = 0
            for game in games where game.status == .final {
                guard let pickedId = pick.picks[game.id] else { continue }
                if let correct = ScoringEngine.isPickCorrect(pickedTeamId: pickedId, game: game) {
                    if correct { wins += 1 } else { losses += 1 }
                }
            }
            let record = WeeklyRecord(week: week.weekNumber, wins: wins, losses: losses)
            weeklyRecords.append(record)
            seasonWins += wins
            seasonLosses += losses
            if bestWeek == nil || wins > (bestWeek?.wins ?? 0) {
                bestWeek = record
            }
        }

        weeklyRecords.sort { $0.week < $1.week }
        let streak = computeStreak(from: weeklyRecords)

        let member = members.first(where: { $0.id == userId })
        return PlayerSeasonStats(
            id: userId,
            displayName: member?.displayName ?? "Player",
            weeklyRecords: weeklyRecords,
            seasonWins: member?.seasonWins ?? seasonWins,
            seasonLosses: member?.seasonLosses ?? seasonLosses,
            currentStreak: streak,
            bestWeekNumber: bestWeek?.week,
            bestWeekWins: bestWeek?.wins,
            bestWeekLosses: bestWeek?.losses
        )
    }

    private func computeStreak(from records: [WeeklyRecord]) -> Int {
        var streak = 0
        for record in records.reversed() {
            if record.wins > record.losses {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    private func deleteWeekData(groupRef: DocumentReference, weekId: String) async throws {
        let weekRef = groupRef.collection("weeks").document(weekId)
        for sub in ["nominations", "games", "picks", "submissions"] {
            let snap = try await weekRef.collection(sub).getDocuments()
            for doc in snap.documents {
                try await doc.reference.delete()
            }
        }
        try await weekRef.delete()
    }

    /// Commissioner renames the league. Keeps local state and the public Discover index in sync.
    func renameGroup(groupId: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 40 else { throw GroupError.invalidGroupName }
        guard let group = groups.first(where: { $0.id == groupId }) ?? selectedGroup,
              group.id == groupId else {
            throw GroupError.groupNotFound
        }
        guard group.commissionerId == Auth.auth().currentUser?.uid else {
            throw GroupError.notCommissioner
        }

        try await db.collection("groups").document(groupId).updateData(["name": trimmed])

        if var g = selectedGroup, g.id == groupId {
            g.name = trimmed
            selectedGroup = g
        }
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].name = trimmed
        }
        if group.isPublic {
            try? await db.collection("publicLeagues").document(groupId).updateData(["name": trimmed])
        }
    }

    /// Commissioner sets a custom invite code (the league "password"). Reserves the new code,
    /// points the group at it, and releases the old code so it can't be reused to join.
    @discardableResult
    func updateInviteCode(groupId: String, newCode rawCode: String) async throws -> String {
        guard let group = groups.first(where: { $0.id == groupId }) ?? selectedGroup,
              group.id == groupId else {
            throw GroupError.groupNotFound
        }
        guard group.commissionerId == Auth.auth().currentUser?.uid else {
            throw GroupError.notCommissioner
        }

        let code = InviteCodeRules.normalize(rawCode)
        guard InviteCodeRules.isValidFormat(code) else {
            throw GroupError.invalidInviteCodeFormat
        }
        if code == group.inviteCode { return code }

        let existing = try await db.collection("inviteCodes").document(code).getDocument()
        if existing.exists { throw GroupError.inviteCodeTaken }

        let previousCode = group.inviteCode
        try await db.collection("inviteCodes").document(code).setData(["groupId": groupId])
        try await db.collection("groups").document(groupId).updateData(["inviteCode": code])
        try? await db.collection("inviteCodes").document(previousCode).delete()

        if var g = selectedGroup, g.id == groupId {
            g.inviteCode = code
            selectedGroup = g
        }
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].inviteCode = code
        }
        if group.isPublic {
            try? await db.collection("publicLeagues").document(groupId).updateData(["inviteCode": code])
        }
        return code
    }

    /// Rolls a fresh random invite code for the league.
    @discardableResult
    func regenerateInviteCode(groupId: String) async throws -> String {
        var code = generateInviteCode()
        for _ in 0..<5 {
            let existing = try await db.collection("inviteCodes").document(code).getDocument()
            if !existing.exists { break }
            code = generateInviteCode()
        }
        return try await updateInviteCode(groupId: groupId, newCode: code)
    }

    /// Commissioner removes another member from the league.
    func removeMember(groupId: String, userId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) ?? selectedGroup,
              group.id == groupId else {
            throw GroupError.groupNotFound
        }
        guard group.commissionerId == Auth.auth().currentUser?.uid else {
            throw GroupError.notCommissioner
        }
        guard userId != group.commissionerId else {
            throw GroupError.cannotRemoveCommissioner
        }
        guard group.memberIds.contains(userId) else { return }

        let updatedIds = group.memberIds.filter { $0 != userId }
        try await db.collection("groups").document(groupId).updateData(["memberIds": updatedIds])
        try await db.collection("groups").document(groupId)
            .collection("members").document(userId).delete()

        if var g = selectedGroup, g.id == groupId {
            g.memberIds = updatedIds
            selectedGroup = g
        }
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].memberIds = updatedIds
        }
        members.removeAll { $0.id == userId }
        if group.isPublic {
            try? await db.collection("publicLeagues").document(groupId)
                .updateData(["memberCount": updatedIds.count])
        }
    }

    func updateRules(groupId: String, rules: GroupRules) async throws {
        try await db.collection("groups").document(groupId).updateData([
            "rules": try Firestore.Encoder().encode(rules)
        ])
        selectedGroup?.rules = rules
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].rules = rules
        }

        // Keep an open selection-week snapshot aligned with the active either/or knob.
        await reconcileSelectionWeekSnapshot(groupId: groupId, rules: rules)
    }

    /// Member-mode weeks store a derived slate size (`members × Selections`). Rewrite it
    /// whenever membership or rules change so UI and nomination limits don't keep the
    /// old commissioner default of 12.
    func reconcileSelectionWeekSnapshot(groupId: String, rules: GroupRules) async {
        guard var week = currentWeek, week.status == .selection, !week.skipsSelection else { return }
        let memberCount = max(selectedGroup?.memberIds.count ?? members.count, 1)
        let expected = rules.expectedSlateSize(memberCount: memberCount)
        guard week.slateSize != expected
            || week.selectionMode != rules.selectionMode
            || week.selectionsPerMember != rules.selectionsPerMember else { return }
        do {
            try await db.week(groupId: groupId, weekId: week.id).updateData([
                "slateSize": expected,
                "selectionMode": rules.selectionMode.rawValue,
                "selectionsPerMember": rules.selectionsPerMember,
            ])
            week.slateSize = expected
            week.selectionMode = rules.selectionMode
            week.selectionsPerMember = rules.selectionsPerMember
            currentWeek = week
        } catch {
            AppLog.error(AppLog.firestore, "selection slate size reconcile failed", error: error, metadata: [
                "group_id": groupId,
                "week_id": week.id,
            ])
        }
    }

    func setPublic(groupId: String, isPublic: Bool) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) ?? selectedGroup,
              group.id == groupId else {
            throw GroupError.groupNotFound
        }
        guard group.commissionerId == Auth.auth().currentUser?.uid else {
            throw GroupError.notCommissioner
        }

        try await db.collection("groups").document(groupId).updateData(["isPublic": isPublic])
        let indexRef = db.collection("publicLeagues").document(groupId)
        if isPublic {
            try await indexRef.setData([
                "groupId": groupId,
                "name": group.name,
                "inviteCode": group.inviteCode,
                "memberCount": group.memberCount,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        } else {
            try await indexRef.delete()
        }

        if var g = selectedGroup, g.id == groupId {
            g.isPublic = isPublic
            selectedGroup = g
        }
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].isPublic = isPublic
        }
    }

    func lockSlateEarly(groupId: String, weekId: String, rules: GroupRules, kickoffs: [Date]) async throws {
        let updates = WeekTransition.lockEarlyUpdates(rules: rules, kickoffs: kickoffs)
        try await db.week(groupId: groupId, weekId: weekId).updateData(updates)
    }

    func resolveTie(groupId: String, standingUserId: String) async throws {
        guard var standings else { return }
        guard let index = standings.entries.firstIndex(where: { $0.id == standingUserId }) else { return }

        let tiedRank = standings.entries[index].rank
        standings.entries[index].isTied = false

        for i in standings.entries.indices where i != index {
            if standings.entries[i].rank == tiedRank && standings.entries[i].isTied {
                standings.entries[i].rank = tiedRank + 1
            }
        }

        standings.entries = ScoringEngine.rankedStandings(
            entries: standings.entries,
            weekly: true,
            tieBreaker: selectedGroup?.rules.tieBreaker ?? .commissionerOverride
        )
        try await db.collection("groups").document(groupId)
            .collection("standings").document("current")
            .setData(from: standings)
    }

    /// Archives the given season year, updates career totals, and resets current-season W–L.
    func closeSeason(groupId: String, seasonYear: Int) async throws {
        guard let group = groups.first(where: { $0.id == groupId })
                ?? selectedGroup,
              group.id == groupId else {
            throw GroupError.groupNotFound
        }
        guard group.commissionerId == Auth.auth().currentUser?.uid else {
            throw GroupError.notCommissioner
        }
        guard !seasonArchives.contains(where: { $0.seasonYear == seasonYear }) else {
            throw GroupError.seasonAlreadyClosed
        }

        isClosingSeason = true
        defer { isClosingSeason = false }

        let groupRef = db.collection("groups").document(groupId)
        let membersSnapshot = try await groupRef.collection("members").getDocuments()
        let currentMembers = membersSnapshot.documents.compactMap { try? $0.data(as: GroupMember.self) }
        guard !currentMembers.isEmpty else {
            throw GroupError.noMembersToArchive
        }

        let weeksSnapshot = try await groupRef.collection("weeks")
            .whereField("seasonYear", isEqualTo: seasonYear)
            .getDocuments()
        let weekCount = weeksSnapshot.documents.count

        let archive = SeasonCloseEngine.makeArchive(
            seasonYear: seasonYear,
            groupId: groupId,
            members: currentMembers,
            weekCount: weekCount
        )

        var careerUpdates: [(DocumentReference, CareerRecord)] = []
        for member in currentMembers {
            let finish = archive.finalStandings.first(where: { $0.id == member.id })?.rank
                ?? archive.finalStandings.count
            let wonTitle = archive.championUserId == member.id
            let careerRef = groupRef.collection("career").document(member.id)
            let existingSnap = try await careerRef.getDocument()
            let existing = try? existingSnap.data(as: CareerRecord.self)
            let updated = SeasonCloseEngine.updatedCareer(
                existing: existing,
                member: member,
                finish: finish,
                wonTitle: wonTitle
            )
            careerUpdates.append((careerRef, updated))
        }

        let batch = db.batch()
        let seasonRef = groupRef.collection("seasons").document(archive.id)
        try batch.setData(from: archive, forDocument: seasonRef)

        for (careerRef, updated) in careerUpdates {
            try batch.setData(from: updated, forDocument: careerRef)
        }

        for member in currentMembers {
            batch.updateData(
                ["seasonWins": 0, "seasonLosses": 0],
                forDocument: groupRef.collection("members").document(member.id)
            )
        }

        if var standings {
            standings.entries = standings.entries.map { entry in
                var copy = entry
                copy.seasonWins = 0
                copy.seasonLosses = 0
                copy.weeklyWins = 0
                copy.weeklyLosses = 0
                return copy
            }
            standings.updatedAt = Date()
            try batch.setData(from: standings, forDocument: groupRef.collection("standings").document("current"))
            self.standings = standings
        }

        try await batch.commit()

        members = currentMembers.map { member in
            var copy = member
            copy.seasonWins = 0
            copy.seasonLosses = 0
            return copy
        }
        careerRecords = careerUpdates.map(\.1)
        if seasonArchives.contains(where: { $0.id == archive.id }) == false {
            seasonArchives = ([archive] + seasonArchives).sorted { $0.seasonYear > $1.seasonYear }
        }
    }

    func careerRecord(for userId: String) -> CareerRecord? {
        careerRecords.first { $0.id == userId }
    }

    /// Fill missing member photo URLs from `users/{uid}` (and mirror onto the member doc).
    private func hydrateMemberAvatars(_ members: [GroupMember]) async -> [GroupMember] {
        var result = members
        for idx in result.indices {
            if let existing = result[idx].avatarImageURL, !existing.isEmpty { continue }
            let userId = result[idx].id
            do {
                let snap = try await db.collection("users").document(userId).getDocument()
                guard let url = snap.data()?["avatarImageURL"] as? String, !url.isEmpty else { continue }
                result[idx].avatarImageURL = url
                // Best-effort mirror so future loads skip the user doc read.
                if let groupId = selectedGroup?.id {
                    try? await db.collection("groups").document(groupId)
                        .collection("members").document(userId)
                        .updateData(["avatarImageURL": url])
                }
            } catch {
                continue
            }
        }
        return result
    }

    private func observeGroupDetails(groupId: String, weekId: String) {
        if observedGroupId == groupId, observedWeekId == weekId, weekListener != nil {
            return
        }

        weekListener?.remove()
        standingsListener?.remove()
        if observedGroupId != groupId {
            seasonsListener?.remove()
            careerListener?.remove()
            observeDynasty(groupId: groupId)
        }
        observedWeekId = weekId
        observedGroupId = groupId

        weekListener = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    // `remove()` does not cancel an already-queued MainActor hop.
                    guard self.observedWeekId == weekId, self.observedGroupId == groupId else { return }
                    if let error {
                        AppEvents.failure(.weekListenerError, error: error, metadata: [
                            "listener": "week",
                            "group_id": groupId,
                            "week_id": weekId,
                        ], recordNonFatal: false)
                        // Keep the last good week — clearing nil here is what made Home twitch.
                        return
                    }
                    guard let snapshot, snapshot.exists else { return }
                    do {
                        let week = try snapshot.data(as: WeekSummary.self)
                        if self.weekSelectionPinned, let current = self.currentWeek, current.id != week.id {
                            return
                        }
                        self.currentWeek = week
                    } catch {
                        AppLog.error(AppLog.firestore, "week decode failed", error: error, metadata: [
                            "group_id": groupId,
                            "week_id": weekId,
                        ])
                    }
                }
            }

        standingsListener = db.collection("groups").document(groupId)
            .collection("standings").document("current")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error {
                        AppEvents.failure(.weekListenerError, error: error, metadata: [
                            "listener": "standings",
                            "group_id": groupId,
                        ], recordNonFatal: false)
                        return
                    }
                    guard let snapshot, snapshot.exists else { return }
                    self?.standings = try? snapshot.data(as: GroupStandings.self)
                }
            }

        Task {
            do {
                let membersSnapshot = try await db.collection("groups").document(groupId)
                    .collection("members").getDocuments()
                var loaded = membersSnapshot.documents.compactMap { try? $0.data(as: GroupMember.self) }
                loaded = await hydrateMemberAvatars(loaded)
                members = loaded
            } catch {
                AppLog.error(AppLog.firestore, "members fetch failed", error: error, metadata: [
                    "group_id": groupId,
                ])
            }
        }
    }

    /// One-shot server fetch for pull-to-refresh. Listeners stay attached.
    func refreshFromServer() async {
        guard let groupId = selectedGroup?.id else { return }
        do {
            let groupSnap = try await db.collection("groups").document(groupId)
                .getDocument(source: .server)
            if let group = try? groupSnap.data(as: PickemGroup.self) {
                selectedGroup = group
                if let idx = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[idx] = group
                }
            }
        } catch {
            UserFacingError.apply(error, to: &errorMessage)
        }

        if let info = try? await ESPNService.shared.currentWeek() {
            cfbWeek = info
        }

        let weekId = currentWeek?.id ?? observedWeekId
        if let weekId {
            do {
                let weekSnap = try await db.collection("groups").document(groupId)
                    .collection("weeks").document(weekId)
                    .getDocument(source: .server)
                if weekSnap.exists, let week = try? weekSnap.data(as: WeekSummary.self) {
                    if !(weekSelectionPinned && currentWeek?.id != week.id) {
                        currentWeek = week
                    }
                }
            } catch {
                UserFacingError.apply(error, to: &errorMessage)
            }

            do {
                let standingsSnap = try await db.collection("groups").document(groupId)
                    .collection("standings").document("current")
                    .getDocument(source: .server)
                if standingsSnap.exists {
                    standings = try? standingsSnap.data(as: GroupStandings.self)
                }
            } catch {
                AppLog.error(AppLog.firestore, "standings refresh failed", error: error, metadata: [
                    "group_id": groupId,
                ])
            }
        }

        do {
            let membersSnapshot = try await db.collection("groups").document(groupId)
                .collection("members")
                .getDocuments(source: .server)
            var loaded = membersSnapshot.documents.compactMap { try? $0.data(as: GroupMember.self) }
            loaded = await hydrateMemberAvatars(loaded)
            members = loaded
        } catch {
            AppLog.error(AppLog.firestore, "members refresh failed", error: error, metadata: [
                "group_id": groupId,
            ])
        }

        await loadAvailableWeeks(groupId: groupId)
    }

    private func clearWeekObservationIfNeeded() {
        weekListener?.remove()
        standingsListener?.remove()
        weekListener = nil
        standingsListener = nil
        observedWeekId = nil
        observedGroupId = nil
        weekSelectionPinned = false
        currentWeek = nil
        availableWeeks = []
        seasonDateRangeByWeekId = [:]
        cfbWeek = nil
        standings = nil
        members = []
    }

    private func observeDynasty(groupId: String) {
        seasonsListener = db.collection("groups").document(groupId)
            .collection("seasons")
            .order(by: "seasonYear", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.seasonArchives = snapshot?.documents.compactMap {
                        try? $0.data(as: SeasonArchive.self)
                    } ?? []
                }
            }

        careerListener = db.collection("groups").document(groupId)
            .collection("career")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    self?.careerRecords = snapshot?.documents.compactMap {
                        try? $0.data(as: CareerRecord.self)
                    } ?? []
                }
            }
    }

    private func backfillInviteCodeIndexes(for userId: String) async {
        for group in groups where group.commissionerId == userId {
            let ref = db.collection("inviteCodes").document(group.inviteCode)
            do {
                let doc = try await ref.getDocument()
                if !doc.exists {
                    try await ref.setData(["groupId": group.id])
                }
            } catch {
                // Non-fatal — join still works once indexed.
            }
        }
    }

    private func generateInviteCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var result = ""
        var remaining = 6
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            randoms.forEach { random in
                if remaining == 0 { return }
                if random < chars.count {
                    result.append(chars[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    enum GroupError: LocalizedError {
        case invalidInviteCode
        case invalidInviteCodeFormat
        case inviteCodeTaken
        case invalidGroupName
        case cannotRemoveCommissioner
        case groupNotFound
        case notCommissioner
        case cannotLeaveAsSoleCommissioner
        case seasonAlreadyClosed
        case noMembersToArchive
        case signInRequired

        var errorDescription: String? {
            switch self {
            case .invalidInviteCode: return "Invalid invite code. Check with your commissioner."
            case .invalidInviteCodeFormat: return "Invite codes are 4–8 letters or numbers."
            case .inviteCodeTaken: return "That code is already in use. Try another."
            case .invalidGroupName: return "League names must be 2–40 characters."
            case .cannotRemoveCommissioner: return "You can't remove yourself as commissioner. Transfer the role or delete the league."
            case .groupNotFound: return "Group not found."
            case .notCommissioner: return "Only the commissioner can do that."
            case .cannotLeaveAsSoleCommissioner: return "Transfer commissioner to someone else before leaving, or delete the league if you're the only member."
            case .seasonAlreadyClosed: return "That season is already archived."
            case .noMembersToArchive: return "No members to archive for this season."
            case .signInRequired: return "Sign in to continue."
            }
        }
    }
}
