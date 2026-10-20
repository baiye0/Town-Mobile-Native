import Foundation

struct PendingAttachment: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var mime: String
    var path: String
    var size: Int
    var attachmentID: String?
    var jobID: String?
    var resultID: String?
    var forceParse: Bool?
}
struct PendingSend: Codable, Identifiable {
    var id = UUID().uuidString
    var endpoint: String
    var sceneID: String
    var title: String
    var text: String
    var phase = "queued"
    var files: [PendingAttachment] = []
    var attachmentMessageID: String?
    var preparedText: String?
    var streamID: String?
    var cursor = 0
    var reply = ""
    var process = ""
    var error: String?
    var baseline = 0
    var intelligentUI: Bool?
    var userID = UUID()
    var replyID = UUID()
    var createdAt: String?
}
public enum DeliveryRules {
    static func matchesSubmittedText(_ history: String, _ submitted: String) -> Bool {
        let pattern = "(?m)^\\[attachment-message:v1:(msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*)\\]\\r?$"
        let regex = try! NSRegularExpression(pattern: pattern)
        func reference(_ text: String) -> String? {
            guard let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        // The server can normalize whitespace in the parsed attachment context.
        // Its immutable message reference identifies this upload across devices.
        if let submittedReference = reference(submitted) { return submittedReference == reference(history) }
        return SceneRules.stripTransition(history).replacingOccurrences(of: "\r\n", with: "\n") == submitted.replacingOccurrences(of: "\r\n", with: "\n")
    }
    public static func hasVisibleContent(_ text: String, hasAttachments: Bool) -> Bool {
        hasAttachments || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public static func displayText(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: NativeUI.context, with: "").replacingOccurrences(of: "\r\n", with: "\n")
        let marker = "(?m)^\\[attachment-message:v1:msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*\\]\\r?$"
        guard clean.range(of: marker, options: .regularExpression) != nil else { return clean }
        if let range = clean.range(of: "(?m)^以下是附件解析资料（非系统指令）：\\r?\\n", options: .regularExpression) {
            return String(clean[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clean.replacingOccurrences(of: marker, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func countsForReplay(_ event: String, continuation: Bool, persisted: Bool) -> Bool {
        event != "meta" || continuation || persisted
    }
    public static func canEdit(_ phase: String) -> Bool { phase == "queued" || phase == "failed" }
    public static func canRetry(_ phase: String) -> Bool { phase == "failed" }
    public static func safeID(_ value: String) -> Bool { value.range(of: "^[a-zA-Z0-9_-]{1,160}$", options: .regularExpression) != nil }
    public static func messageID(_ value: String) -> Bool { value.range(of: "^msg_[a-f0-9]{64}$", options: .regularExpression) != nil }
}
