import Foundation

enum LiveScoreRefresh {
    static func start(
        existing task: Task<Void, Never>?,
        interval: Duration = LiveRefreshPolicy.refreshInterval,
        refresh: @escaping () async -> Void
    ) -> Task<Void, Never> {
        task?.cancel()
        return Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    static func stop(_ task: inout Task<Void, Never>?) {
        task?.cancel()
        task = nil
    }
}
