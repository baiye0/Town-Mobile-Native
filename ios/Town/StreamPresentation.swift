import Foundation

/// Bound UI work to 30 reply frames / 10 progress frames per second. A pending
/// text update cannot be downgraded by a later thinking packet. Flush always
/// delivers the trailing snapshot before completion or cancellation.
@MainActor final class StreamPresentation {
    private var pending: PendingSend?
    private var pendingProgressOnly = true
    private var task: Task<Void, Never>?
    private var interval: Duration = .milliseconds(33)
    private let publish: (PendingSend) -> Void
    private let publishProgress: (PendingSend) -> Void
    init(publish: @escaping (PendingSend) -> Void, publishProgress: ((PendingSend) -> Void)? = nil) {
        self.publish = publish; self.publishProgress = publishProgress ?? publish
    }
    func submit(_ entry: PendingSend, progressOnly: Bool = false) {
        interval = progressOnly ? .milliseconds(100) : .milliseconds(33)
        guard task != nil else {
            deliver(entry, progressOnly: progressOnly)
            task = Task { [weak self] in
                while !Task.isCancelled {
                    let delay = self?.interval ?? .milliseconds(33)
                    do { try await Task.sleep(for: delay) } catch { return }
                    guard let self else { return }
                    guard let next = self.pending else { self.task = nil; return }
                    let onlyProgress = self.pendingProgressOnly
                    self.pending = nil; self.pendingProgressOnly = true
                    self.deliver(next, progressOnly: onlyProgress)
                }
            }
            return
        }
        pending = entry
        pendingProgressOnly = pendingProgressOnly && progressOnly
    }
    private func deliver(_ entry: PendingSend, progressOnly: Bool) {
        if progressOnly { publishProgress(entry) } else { publish(entry) }
    }
    func flush() {
        task?.cancel(); task = nil
        guard let entry = pending else { return }
        let onlyProgress = pendingProgressOnly
        pending = nil; pendingProgressOnly = true
        deliver(entry, progressOnly: onlyProgress)
    }
    deinit { task?.cancel() }
}
