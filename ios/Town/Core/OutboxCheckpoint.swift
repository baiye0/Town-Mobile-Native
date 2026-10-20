import Foundation

/// A single writer preserves snapshot order across periodic stream checkpoints
/// and synchronous send/stop/delete commits. Old async writes cannot resurrect
/// an already removed queue entry or overwrite a newer replay cursor.
enum OutboxCheckpoint {
    private static let queue = DispatchQueue(label: "town.outbox.persistence", qos: .utility)

    static func save(_ entries: [PendingSend], to url: URL) throws {
        try queue.sync { try write(entries, to: url) }
    }

    static func schedule(_ entries: [PendingSend], to url: URL, onError: @escaping @Sendable () -> Void) {
        queue.async {
            do { try write(entries, to: url) }
            catch { onError() }
        }
    }

    private static func write(_ entries: [PendingSend], to url: URL) throws {
        try JSONEncoder().encode(entries).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
