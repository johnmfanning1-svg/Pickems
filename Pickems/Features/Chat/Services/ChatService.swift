import Foundation
import FirebaseFirestore

/// Firestore-backed group chat.
///
/// Listener lifecycle mirrors `PickService`: one `ListenerRegistration` held in
/// `@ObservationIgnored` storage, removed and reattached whenever the observed
/// group changes. The listener owns the newest page; older pages are fetched
/// on demand and kept separately so a snapshot refresh can't discard history.
@MainActor
@Observable
final class ChatService {
    /// One page of history. Matches the plan's 50-message window.
    static let pageSize = 50
    /// Cap on the unread badge so a member who has never opened chat still costs
    /// one bounded query instead of a full-collection count.
    static let unreadBadgeCap = 20
    /// A message is auto-hidden by `onReportCreated` at this many reports.
    static let autoHideReportThreshold = 3

    /// Newest page, owned by the snapshot listener.
    private(set) var liveMessages: [ChatMessage] = []
    /// Older pages fetched by `loadOlderMessages()`.
    private(set) var olderMessages: [ChatMessage] = []
    /// Optimistic local echoes, dropped once the server confirms the same id.
    private(set) var pendingMessages: [ChatMessage] = []

    var errorMessage: String?
    var isSending = false
    var isLoadingOlder = false
    var hasMoreHistory = false
    /// `appConfig/live.chatEnabled`. Defaults to enabled: the flag is a kill
    /// switch, so an unreadable or missing config must not take chat down.
    var chatEnabled = true
    var observedGroupId: String?
    /// `chatMuted` on the caller's member doc — suppresses the push fan-out.
    var isMuted = false
    private(set) var blockedUserIds: Set<String> = []
    private(set) var hiddenMessageIds: Set<String> = []

    @ObservationIgnored
    private lazy var db = Firestore.firestore()
    @ObservationIgnored
    private var listener: ListenerRegistration?
    /// Last doc of the listener's window — the starting cursor for pagination.
    @ObservationIgnored
    private var liveWindowLastDocument: DocumentSnapshot?
    /// Advances as older pages load, so a listener refresh can't rewind paging.
    @ObservationIgnored
    private var historyCursor: DocumentSnapshot?
    @ObservationIgnored
    private var blocklist: ChatBlocklist?
    @ObservationIgnored
    private var didLoadRemoteConfig = false

    // MARK: - Derived state

    /// Oldest → newest, with blocked authors and locally hidden messages removed.
    var visibleMessages: [ChatMessage] {
        let confirmedIds = Set(liveMessages.map(\.id))
        let unconfirmed = pendingMessages.filter { !confirmedIds.contains($0.id) }
        return (liveMessages + olderMessages + unconfirmed)
            .filter { !blockedUserIds.contains($0.userId) }
            .filter { !hiddenMessageIds.contains($0.id) }
            .sorted { $0.sortDate < $1.sortDate }
    }

    // MARK: - Listener lifecycle

    func observe(groupId: String, userId: String) {
        guard observedGroupId != groupId || listener == nil else { return }
        listener?.remove()
        listener = nil
        observedGroupId = groupId
        liveMessages = []
        olderMessages = []
        pendingMessages = []
        liveWindowLastDocument = nil
        historyCursor = nil
        hasMoreHistory = false
        errorMessage = nil
        loadLocalModerationState(userId: userId)

        listener = db.group(groupId).messages
            .order(by: FirestoreField.createdAt, descending: true)
            .limit(to: Self.pageSize)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.observedGroupId == groupId else { return }
                    if let error {
                        UserFacingError.apply(error, to: &self.errorMessage, context: .listener)
                        AppEvents.failure(.chatListenerError, error: error, metadata: [
                            "group_id": groupId,
                        ], recordNonFatal: false)
                        return
                    }
                    guard let snapshot else { return }
                    self.liveMessages = snapshot.documents.compactMap {
                        try? $0.data(as: ChatMessage.self)
                    }
                    let confirmedIds = Set(self.liveMessages.map(\.id))
                    self.pendingMessages.removeAll { confirmedIds.contains($0.id) }
                    self.liveWindowLastDocument = snapshot.documents.last
                    if self.historyCursor == nil {
                        self.hasMoreHistory = snapshot.documents.count == Self.pageSize
                    }
                }
            }
    }

    func stopObserving() {
        listener?.remove()
        listener = nil
        observedGroupId = nil
        liveMessages = []
        olderMessages = []
        pendingMessages = []
        liveWindowLastDocument = nil
        historyCursor = nil
        hasMoreHistory = false
    }

    func loadOlderMessages() async {
        guard let groupId = observedGroupId,
              hasMoreHistory,
              !isLoadingOlder,
              let cursor = historyCursor ?? liveWindowLastDocument else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let snapshot = try await db.group(groupId).messages
                .order(by: FirestoreField.createdAt, descending: true)
                .start(afterDocument: cursor)
                .limit(to: Self.pageSize)
                .getDocuments()
            let known = Set((liveMessages + olderMessages).map(\.id))
            let page = snapshot.documents
                .compactMap { try? $0.data(as: ChatMessage.self) }
                .filter { !known.contains($0.id) }
            olderMessages.append(contentsOf: page)
            if let last = snapshot.documents.last {
                historyCursor = last
            }
            hasMoreHistory = snapshot.documents.count == Self.pageSize
        } catch {
            UserFacingError.apply(error, to: &errorMessage)
            AppEvents.failure(.chatHistoryLoadFailed, error: error, metadata: [
                "group_id": groupId,
            ], recordNonFatal: false)
        }
    }

    // MARK: - Sending

    func send(text rawText: String, groupId: String, weekId: String?, author: UserProfile) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= ChatMessage.maxTextLength else { return }

        let ref = db.group(groupId).messages.document()
        // `createdAt` has to be the server clock: the rules pin it to `request.time`,
        // which is what makes thread order untamperable. A pending server timestamp
        // reads back as nil locally, so the echo below carries the thread instead.
        var payload: [String: Any] = [
            "id": ref.documentID,
            "groupId": groupId,
            "userId": author.id,
            "displayName": author.displayName,
            "avatarColorHex": author.avatarColorHex,
            "text": text,
            FirestoreField.createdAt: FieldValue.serverTimestamp(),
            FirestoreField.isDeleted: false,
            "reportCount": 0,
        ]
        if let weekId {
            payload["weekId"] = weekId
        }

        let echo = ChatMessage(
            id: ref.documentID,
            groupId: groupId,
            weekId: weekId,
            userId: author.id,
            displayName: author.displayName,
            avatarColorHex: author.avatarColorHex,
            text: text,
            createdAt: nil,
            editedAt: nil,
            isDeleted: false,
            reactions: nil,
            reportCount: 0
        )
        pendingMessages.append(echo)
        isSending = true
        defer { isSending = false }

        do {
            try await ref.setData(payload)
            errorMessage = nil
            AppEvents.track(.chatMessageSent, metadata: [
                "group_id": groupId,
                "week_id": weekId ?? "league",
            ])
        } catch {
            pendingMessages.removeAll { $0.id == echo.id }
            UserFacingError.apply(error, to: &errorMessage, context: .write)
            AppEvents.failure(.chatSendFailed, error: error, metadata: ["group_id": groupId])
        }
    }

    // MARK: - Moderation (App Review Guideline 1.2)

    /// Soft delete. Rules let an author touch only `text`, `editedAt`, `isDeleted`,
    /// and the placeholder keeps surrounding replies readable.
    func deleteOwnMessage(_ message: ChatMessage, userId: String) async {
        guard message.userId == userId else { return }
        do {
            try await db.group(message.groupId).messages.document(message.id)
                .updateData([FirestoreField.isDeleted: true])
            AppEvents.track(.chatMessageDeleted, metadata: ["group_id": message.groupId])
        } catch {
            UserFacingError.apply(error, to: &errorMessage, context: .write)
            AppEvents.failure(.chatMessageDeleteFailed, error: error, metadata: [
                "group_id": message.groupId,
            ])
        }
    }

    /// Writes `messages/{id}/reports/{reporterUid}` and hides the message locally.
    /// `reportCount` is a Cloud Function's job — the client can't and shouldn't move it.
    func report(_ message: ChatMessage, reason: ChatReportReason, reporterId: String) async throws {
        do {
            try await db.group(message.groupId).messages.document(message.id)
                .reports.document(reporterId)
                .setData([
                    "reporterUid": reporterId,
                    "reason": reason.rawValue,
                    FirestoreField.createdAt: FieldValue.serverTimestamp(),
                ])
            hide(messageId: message.id)
            AppEvents.track(.chatMessageReported, metadata: [
                "group_id": message.groupId,
                "reason": reason.rawValue,
            ])
        } catch {
            AppEvents.failure(.chatMessageReportFailed, error: error, metadata: [
                "group_id": message.groupId,
            ])
            throw error
        }
    }

    func block(userId: String, ownerId: String) {
        loadLocalModerationState(userId: ownerId)
        guard let blocklist else { return }
        blockedUserIds = blocklist.block(userId)
        AppEvents.track(.chatUserBlocked, metadata: ["uid": AppEvents.shortUID(userId)])
    }

    func unblock(userId: String, ownerId: String) {
        loadLocalModerationState(userId: ownerId)
        guard let blocklist else { return }
        blockedUserIds = blocklist.unblock(userId)
        AppEvents.track(.chatUserUnblocked, metadata: ["uid": AppEvents.shortUID(userId)])
    }

    func isBlocked(_ userId: String) -> Bool {
        blockedUserIds.contains(userId)
    }

    private func hide(messageId: String) {
        guard let blocklist else { return }
        hiddenMessageIds = blocklist.hide(messageId: messageId)
    }

    /// Idempotent: safe to call from any entry point before the listener attaches.
    func loadLocalModerationState(userId: String) {
        let list = ChatBlocklist(ownerId: userId)
        blocklist = list
        blockedUserIds = list.blockedUserIds
        hiddenMessageIds = list.hiddenMessageIds
    }

    // MARK: - Read state, mute, unread badge

    func markRead(groupId: String, userId: String) async {
        do {
            try await db.group(groupId).members.document(userId)
                .setData([FirestoreField.lastReadChatAt: FieldValue.serverTimestamp()], merge: true)
        } catch {
            // Cosmetic: a stale badge is not worth a banner.
            AppLog.notice(AppLog.firestore, "chat lastReadChatAt write failed", metadata: [
                "group_id": groupId,
                "error": AppLog.describe(error),
            ])
        }
    }

    func loadMuteState(groupId: String, userId: String) async {
        do {
            let snapshot = try await db.group(groupId).members.document(userId).getDocument()
            isMuted = snapshot.data()?[FirestoreField.chatMuted] as? Bool ?? false
        } catch {
            isMuted = false
        }
    }

    func setMuted(_ muted: Bool, groupId: String, userId: String) async {
        isMuted = muted
        do {
            try await db.group(groupId).members.document(userId)
                .setData([FirestoreField.chatMuted: muted], merge: true)
        } catch {
            isMuted = !muted
            UserFacingError.apply(error, to: &errorMessage, context: .write)
        }
    }

    /// Messages since the caller's `lastReadChatAt`, excluding their own, capped at
    /// `unreadBadgeCap`. Returns `unreadBadgeCap + 1` when there are more.
    func unreadCount(groupId: String, userId: String) async -> Int {
        do {
            let memberSnapshot = try await db.group(groupId).members.document(userId).getDocument()
            let lastRead = (memberSnapshot.data()?[FirestoreField.lastReadChatAt] as? Timestamp)?.dateValue()

            var query = db.group(groupId).messages
                .order(by: FirestoreField.createdAt, descending: true)
                .limit(to: Self.unreadBadgeCap + 1)
            if let lastRead {
                query = db.group(groupId).messages
                    .whereField(FirestoreField.createdAt, isGreaterThan: Timestamp(date: lastRead))
                    .order(by: FirestoreField.createdAt, descending: true)
                    .limit(to: Self.unreadBadgeCap + 1)
            }

            let snapshot = try await query.getDocuments()
            let blocked = blockedUserIds
            let hidden = hiddenMessageIds
            return snapshot.documents
                .compactMap { try? $0.data(as: ChatMessage.self) }
                .filter { $0.userId != userId && !$0.isDeleted }
                .filter { !blocked.contains($0.userId) && !hidden.contains($0.id) }
                .count
        } catch {
            AppLog.notice(AppLog.firestore, "chat unread count unavailable", metadata: [
                "group_id": groupId,
                "error": AppLog.describe(error),
            ])
            return 0
        }
    }

    // MARK: - Remote kill switch

    /// Reads `appConfig/live.chatEnabled` once per launch. Chat can be pulled
    /// without shipping a build; an absent doc or field leaves it on.
    func refreshRemoteConfig(force: Bool = false) async {
        guard force || !didLoadRemoteConfig else { return }
        didLoadRemoteConfig = true
        do {
            let snapshot = try await db.liveAppConfig.getDocument()
            if let enabled = snapshot.data()?[FirestoreField.chatEnabled] as? Bool {
                chatEnabled = enabled
            }
        } catch {
            AppLog.notice(AppLog.firestore, "appConfig/live unreadable — chat stays enabled", metadata: [
                "error": AppLog.describe(error),
            ])
        }
    }
}
