import Foundation
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
    var cfbWeek: CFBWeekInfo?
    var seasonArchives: [SeasonArchive] = []
    var careerRecords: [CareerRecord] = []
    var isLoading = false
    var isClosingSeason = false
    var errorMessage: String?

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

    func loadGroups(for userId: String) {
        groupListener?.remove()
        AppLog.info(AppLog.firestore, "loadGroups listener attached", metadata: [
            "uid": AppEvents.shortUID(userId),
        ])
        groupListener = db.collection("groups")
            .whereField("memberIds", arrayContains: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
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
                    Task { @MainActor in
                        await self.backfillInviteCodeIndexes(for: userId)
                    }
                    if self.selectedGroup == nil {
                        self.selectedGroup = self.groups.first
                    }
                    if let groupId = self.selectedGroup?.id {
                        await self.syncCurrentWeekFromESPN(groupId: groupId)
                    }
                    CrashReport.setValue("\(self.groups.count)", forKey: "group_count")
                }
            }
    }

    func selectGroup(_ group: PickemGroup) {
        selectedGroup = group
        Task {
            await syncCurrentWeekFromESPN(groupId: group.id)
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

        let weekId = CFBWeekSync.weekId(for: weekInfo)
        let weekChanged = cfbWeek?.weekNumber != weekInfo.weekNumber
            || cfbWeek?.seasonYear != weekInfo.seasonYear
            || observedWeekId != weekId

        cfbWeek = weekInfo

        guard weekChanged || currentWeek == nil else { return }

        isLoading = currentWeek == nil
        defer { isLoading = false }

        let weekRef = db.collection("groups").document(groupId)
            .collection("weeks").document(weekId)

        do {
            let snapshot = try await weekRef.getDocument()
            if !snapshot.exists {
                let week = CFBWeekSync.makeWeekSummary(id: weekId, info: weekInfo, rules: rules)
                try await weekRef.setData(from: week)
            }
        } catch {
            UserFacingError.apply(error, to: &errorMessage)
        }

        observeGroupDetails(groupId: groupId, weekId: weekId)
    }

    func createGroup(name: String, commissionerId: String, displayName: String) async throws -> PickemGroup {
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
                avatarColorHex: AvatarColors.randomHex(),
                role: .commissioner,
                joinedAt: Date(),
                seasonWins: 0,
                seasonLosses: 0
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

    func joinGroup(inviteCode: String, userId: String, displayName: String, avatarColorHex: String) async throws {
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

        group.memberIds.append(userId)
        try await doc.reference.updateData(["memberIds": group.memberIds])

        let member = GroupMember(
            id: userId,
            displayName: displayName,
            avatarColorHex: avatarColorHex,
            role: .member,
            joinedAt: Date(),
            seasonWins: 0,
            seasonLosses: 0
        )
        try await doc.reference.collection("members").document(userId).setData(from: member)
        selectedGroup = group
        await syncCurrentWeekFromESPN(groupId: group.id)
    }

    /// Keeps league member rows in sync when a user changes their unique display name.
    func syncMemberDisplayName(userId: String, displayName: String) async {
        for group in groups {
            let ref = db.collection("groups").document(group.id)
                .collection("members").document(userId)
            do {
                try await ref.updateData(["displayName": displayName])
                if let idx = members.firstIndex(where: { $0.id == userId }),
                   selectedGroup?.id == group.id {
                    members[idx].displayName = displayName
                }
            } catch {
                AppLog.error(AppLog.firestore, "member displayName sync failed", error: error, metadata: [
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

        if group.commissionerId == userId {
            if group.memberIds.count == 1 {
                try await deleteGroup(groupId: groupId)
                return
            }
            guard let successor = group.memberIds.first(where: { $0 != userId }) else {
                throw GroupError.cannotLeaveAsSoleCommissioner
            }
            try await transferCommissioner(groupId: groupId, toUserId: successor)
        }

        var updatedIds = group.memberIds.filter { $0 != userId }
        try await db.collection("groups").document(groupId).updateData(["memberIds": updatedIds])
        try await db.collection("groups").document(groupId)
            .collection("members").document(userId).delete()

        groups.removeAll { $0.id == groupId }
        if selectedGroup?.id == groupId {
            selectedGroup = groups.first
            if let next = selectedGroup {
                await syncCurrentWeekFromESPN(groupId: next.id)
            } else {
                currentWeek = nil
                standings = nil
                members = []
                seasonArchives = []
                careerRecords = []
            }
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
        try await groupRef.delete()

        groups.removeAll { $0.id == groupId }
        if selectedGroup?.id == groupId {
            selectedGroup = groups.first
            currentWeek = nil
            standings = nil
            self.members = []
            seasonArchives = []
            careerRecords = []
        }
    }

    func transferCommissioner(groupId: String, toUserId: String) async throws {
        guard let group = groups.first(where: { $0.id == groupId }) else {
            throw GroupError.groupNotFound
        }
        let previousCommissionerId = group.commissionerId

        try await db.collection("groups").document(groupId).updateData(["commissionerId": toUserId])
        try await db.collection("groups").document(groupId)
            .collection("members").document(toUserId)
            .updateData(["role": GroupMember.MemberRole.commissioner.rawValue])
        if previousCommissionerId != toUserId {
            try await db.collection("groups").document(groupId)
                .collection("members").document(previousCommissionerId)
                .updateData(["role": GroupMember.MemberRole.member.rawValue])
        }
        if var group = groups.first(where: { $0.id == groupId }) {
            group.commissionerId = toUserId
            if let idx = groups.firstIndex(where: { $0.id == groupId }) {
                groups[idx] = group
            }
            if selectedGroup?.id == groupId {
                selectedGroup = group
            }
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
            let games = gamesSnap.documents.compactMap { try? $0.data(as: SlateGame.self) }
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

        let code = rawCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        guard code.count >= 4, code.count <= 8,
              code.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
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

    private func observeGroupDetails(groupId: String, weekId: String) {
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
                    if let error {
                        AppEvents.failure(.weekListenerError, error: error, metadata: [
                            "listener": "week",
                            "group_id": groupId,
                            "week_id": weekId,
                        ], recordNonFatal: false)
                    }
                    self?.currentWeek = try? snapshot?.data(as: WeekSummary.self)
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
                    }
                    self?.standings = try? snapshot?.data(as: GroupStandings.self)
                }
            }

        Task {
            do {
                let membersSnapshot = try await db.collection("groups").document(groupId)
                    .collection("members").getDocuments()
                members = membersSnapshot.documents.compactMap { try? $0.data(as: GroupMember.self) }
            } catch {
                AppLog.error(AppLog.firestore, "members fetch failed", error: error, metadata: [
                    "group_id": groupId,
                ])
            }
        }
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
        return String((0..<6).map { _ in chars.randomElement() ?? "A" })
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
            case .notCommissioner: return "Only the commissioner can delete this group."
            case .cannotLeaveAsSoleCommissioner: return "Transfer commissioner role or delete the group before leaving."
            case .seasonAlreadyClosed: return "That season is already archived."
            case .noMembersToArchive: return "No members to archive for this season."
            case .signInRequired: return "Sign in to continue."
            }
        }
    }
}
