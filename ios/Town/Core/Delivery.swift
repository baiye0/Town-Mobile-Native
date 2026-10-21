import Foundation

struct PendingAttachment: Codable, Identifiable, Equatable, Sendable {
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
struct PendingSend: Codable, Identifiable, Sendable {
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
    var bubbles: [StreamReply]?
    var process = ""
    var error: String?
    var baseline = 0
    var intelligentUI: Bool?
    var intelligentUISelection: String?
    var userID = UUID()
    var replyID = UUID()
    var createdAt: String?
    var afterID: UUID?
}
public enum DeliveryRules {
    // The reply indicator covers ordinary delivery. Keep actionable queue and
    // failure information on the bubble, without calling a live reply "sending".
    static func bubbleStatus(_ entry: PendingSend) -> String? {
        switch entry.phase {
        case "queued": return entry.files.isEmpty ? "排队中" : "等待上传附件"
        case "preparing": return entry.files.isEmpty ? nil : "正在准备附件"
        case "sending": return nil
        case "waiting": return entry.reply.isEmpty ? "服务端排队中" : nil
        case "failed": return "发送失败"
        case "unknown": return "发送结果待确认"
        case "stopped": return "已停止"
        default: return nil
        }
    }

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
        func normalized(_ text: String) -> String {
            SceneRules.stripTransition(ClientUIContext.strip(text, capabilitiesOnly: true))
                .replacingOccurrences(of: "\r\n", with: "\n")
        }
        return normalized(history) == normalized(submitted)
    }
    public static func hasVisibleContent(_ text: String, hasAttachments: Bool) -> Bool {
        hasAttachments || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public static func displayText(_ text: String) -> String {
        let clean = ClientUIContext.strip(text).replacingOccurrences(of: "\r\n", with: "\n")
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
