import Foundation

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
