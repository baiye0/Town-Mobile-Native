import Foundation

/// Enqueue in mutation order, before yielding the main actor. All snapshots for a
/// file (including the save that acknowledges delivery) use the same serial writer.
enum SnapshotFileWriter {
    private static let queue = DispatchQueue(label: "town.history.persistence", qos: .utility)
    static func enqueue<T: Encodable & Sendable>(_ snapshot: T, to url: URL,
                                                completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            do {
                try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
                completion(true)
            } catch { completion(false) }
        }
    }
}
