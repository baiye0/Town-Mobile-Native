import Foundation

/// Publish the first packet immediately, then at most once per display frame.
/// Every snapshot contains all received text; this never simulates typing.
@MainActor final class StreamPresentation {
    private var pending: PendingSend?
    private var task: Task<Void, Never>?
    private let publish: (PendingSend) -> Void
    init(publish: @escaping (PendingSend) -> Void) { self.publish = publish }
    func submit(_ entry: PendingSend) {
        guard task != nil else {
            publish(entry)
            task = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                    guard let self else { return }
                    guard let next = self.pending else { self.task = nil; return }
                    self.pending = nil
                    self.publish(next)
                }
            }
            return
        }
        pending = entry
    }
    func flush() {
        task?.cancel(); task = nil
        guard let entry = pending else { return }
        pending = nil; publish(entry)
    }
    deinit { task?.cancel() }
}
