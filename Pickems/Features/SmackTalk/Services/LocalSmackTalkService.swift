import Foundation

/// Local persistence for demo and offline-first development.
/// Messages are stored per week thread and survive app restarts.
@MainActor
final class LocalSmackTalkService: ObservableObject, SmackTalkServing {
    @Published private(set) var messagesByThread: [String: [SmackTalkMessage]] = [:]

    private let storageKey = "pickems.smackTalk.messages"
    private var observers: [String: [( [SmackTalkMessage]) -> Void]] = [:]

    init(loadImmediately: Bool = true) {
        if loadImmediately {
            messagesByThread = Self.loadMessages(from: storageKey)
        }
    }

    func messages(for thread: WeekThread) -> [SmackTalkMessage] {
        messagesByThread[thread.id, default: []]
    }

    func observeMessages(for thread: WeekThread, onChange: @escaping ([SmackTalkMessage]) -> Void) {
        observers[thread.id, default: []].append(onChange)
        onChange(messages(for: thread))
    }

    func stopObserving(for thread: WeekThread) {
        observers.removeValue(forKey: thread.id)
    }

    func sendMessage(text: String, context: SmackTalkContext) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SmackTalkError.emptyMessage
        }
        guard trimmed.count <= SmackTalkTextBuilder.maxMessageLength else {
            throw SmackTalkError.messageTooLong
        }

        let message = SmackTalkMessage(
            id: UUID().uuidString,
            threadId: context.thread.id,
            userId: context.userId,
            displayName: context.displayName,
            text: trimmed,
            createdAt: Date(),
            kind: .user
        )

        append(message, to: context.thread)
    }

    func postSystemMessage(text: String, thread: WeekThread) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = SmackTalkMessage(
            id: UUID().uuidString,
            threadId: thread.id,
            userId: "system",
            displayName: "Pickems",
            text: trimmed,
            createdAt: Date(),
            kind: .system
        )

        append(message, to: thread)
    }

    func seedDemoMessagesIfNeeded(for thread: WeekThread) {
        guard messages(for: thread).isEmpty else { return }

        let opener = SmackTalkMessage(
            id: "seed-open-\(thread.id)",
            threadId: thread.id,
            userId: "system",
            displayName: "Pickems",
            text: SmackTalkTextBuilder.weekOpenMessage(for: thread),
            createdAt: Date().addingTimeInterval(-3600),
            kind: .system
        )

        append(opener, to: thread, persist: false)

        for seed in SmackTalkDemoData.seedMessages(for: thread) {
            append(seed, to: thread, persist: false)
        }

        persist()
        notifyObservers(for: thread.id)
    }

    private func append(_ message: SmackTalkMessage, to thread: WeekThread, persist: Bool = true) {
        var threadMessages = messagesByThread[thread.id, default: []]
        threadMessages.append(message)
        threadMessages.sort { $0.createdAt < $1.createdAt }
        messagesByThread[thread.id] = threadMessages

        if persist {
            persist()
        }
        notifyObservers(for: thread.id)
    }

    private func notifyObservers(for threadId: String) {
        let current = messagesByThread[threadId, default: []]
        observers[threadId]?.forEach { $0(current) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(messagesByThread) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func loadMessages(from key: String) -> [String: [SmackTalkMessage]] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: [SmackTalkMessage]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }
}

#if DEBUG
extension LocalSmackTalkService {
    func resetAllMessages() {
        messagesByThread = [:]
        UserDefaults.standard.removeObject(forKey: storageKey)
        observers.keys.forEach { notifyObservers(for: $0) }
    }
}
#endif
