import Foundation

/// Coalesces token bursts into at most one UI update per 50 ms, without dropping
/// any stream data. Flush the last snapshot on completion, failure or cancel.
@MainActor final class StreamPresentation {
    private var pending: PendingSend?
    private var task: Task<Void, Never>?
    private let publish: (PendingSend) -> Void

    init(publish: @escaping (PendingSend) -> Void) { self.publish = publish }

    func submit(_ entry: PendingSend) {
        pending = entry
        guard task == nil else { return }
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
            self?.flush()
        }
    }

    func flush() {
        task?.cancel()
        task = nil
        guard let entry = pending else { return }
        pending = nil
        publish(entry)
    }

    deinit { task?.cancel() }
}

// Parse bytes away from the main actor; only complete SSE frames cross to UI
// state. Awaiting each handler provides backpressure and preserves event order.
enum SSETransport {
    nonisolated static func read(_ bytes: URLSession.AsyncBytes,
                                 onEvent: @MainActor (SSEEvent) throws -> Void) async throws {
        var parser = SSEByteParser()
        for try await byte in bytes {
            try Task.checkCancellation()
            if let event = try parser.consume(byte) { try await onEvent(event) }
        }
        if let event = parser.finish() { try await onEvent(event) }
    }
}
