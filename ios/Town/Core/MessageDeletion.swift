import Foundation

// Local display tombstones. The server's history remains authoritative for
// delivery reconciliation, so filtering happens after merging, not before it.
struct MessageDeletion: Codable {
    var endpoint: String
    var sceneID: String?
    var role: String
    var messageID: UUID
    var sequence: Int?
    var attachmentReference: String?
    var baseline: Int?

    init(_ message: Message, endpoint: String) {
        self.endpoint = endpoint
        sceneID = message.sceneID
        role = message.role
        messageID = message.id
        sequence = message.sequence
        attachmentReference = Self.reference(message.text)
        baseline = message.localBaseline
    }

    func matches(_ message: Message, endpoint: String) -> Bool {
        guard self.endpoint == endpoint, sceneID == message.sceneID, role == message.role else { return false }
        if messageID == message.id { return true }
        if let sequence { return sequence == message.sequence }
        // An uncertain attachment can appear in history after local deletion.
        // Match its immutable upload reference, never its filename or caption.
        guard let attachmentReference, attachmentReference == Self.reference(message.text) else { return false }
        return message.sequence.map { $0 > (baseline ?? 0) } ?? true
    }

    private static func reference(_ text: String) -> String? {
        let pattern = "(?m)^\\[attachment-message:v1:msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*\\]\\r?$"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
