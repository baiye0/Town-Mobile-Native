import Foundation

struct StreamReply: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var text = ""
    var sequence: Int?
    var closed = false
    var interim = false
    var paragraphBreak = false
}

/// Town-Client semantics: tool/reasoning text shares a reply bubble;
/// message_stop ends that bubble, while only transport completion ends the turn.
enum ReplyStream {
    static func consume(_ type: String, _ value: [String: Any], entry: inout PendingSend) {
        var bubbles = entry.bubbles ?? (entry.reply.isEmpty ? [] : [StreamReply(id: entry.replyID, text: entry.reply)])
        let delta = value["delta"] as? [String: Any]
        let text: String?
        switch type {
        case "content_block_delta":
            text = delta?["text"] as? String
        case "text", "message": text = (value["text"] ?? value["content"]) as? String
        default: text = nil
        }
        if let text, !text.isEmpty {
            if bubbles.isEmpty || bubbles.last?.closed == true {
                bubbles.append(StreamReply(id: bubbles.isEmpty ? entry.replyID : UUID()))
            }
            let i = bubbles.count - 1
            let separator = bubbles[i].paragraphBreak && !bubbles[i].text.isEmpty ? "\n\n" : ""
            bubbles[i].text += separator + text
            bubbles[i].paragraphBreak = false
            bubbles[i].interim = false
        } else if !bubbles.isEmpty {
            let i = bubbles.count - 1
            switch type {
            case "tool_use":
                bubbles[i].paragraphBreak = true
                bubbles[i].interim = true
            case "thinking", "reasoning":
                if !reasoningText(value).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    bubbles[i].paragraphBreak = true
                    bubbles[i].interim = true
                }
            case "content_block_delta":
                if let thinking = delta?["thinking"] as? String, !thinking.isEmpty {
                    bubbles[i].paragraphBreak = true
                    bubbles[i].interim = true
                }
            case "message_stop": bubbles[i].closed = true
            case "meta":
                if let persisted = value["persisted"] as? [String: Any],
                   persisted["kind"] as? String == "self", let seq = persisted["seq"] as? Int, seq > 0,
                   let stream = persisted["stream_id"] as? String, !stream.isEmpty,
                   entry.streamID == nil || entry.streamID == stream,
                   let from = persisted["from"] as? String, ["final", "partial", "act_talk"].contains(from),
                   !bubbles.contains(where: { $0.sequence == seq }) {
                    bubbles[i].sequence = seq
                    if from != "final" { bubbles[i].interim = true; bubbles[i].closed = true }
                }
            default: break
            }
        }
        entry.bubbles = bubbles
        entry.reply = bubbles.map(\.text).joined(separator: "\n\n")
    }

    static func finish(_ entry: inout PendingSend) {
        guard let last = entry.bubbles?.indices.last else { return }
        entry.bubbles?[last].closed = true
    }

    static func isProgress(_ type: String, _ value: [String: Any], scene: String) -> Bool {
        if value["scene_id"] is NSNull { return false }
        if let actual = value["scene_id"] as? String, actual != scene { return false }
        if ["tool_use", "tool_result"].contains(type) { return true }
        if type == "content_block_delta" {
            let delta = value["delta"] as? [String: Any] ?? [:]
            return !((delta["text"] ?? delta["thinking"]) as? String ?? "").isEmpty
        }
        if ["thinking", "reasoning"].contains(type) { return !reasoningText(value).isEmpty }
        if ["text", "message"].contains(type) {
            return !((value["text"] ?? value["content"]) as? String ?? "").isEmpty
        }
        return false
    }

    static func reasoningText(_ value: [String: Any]) -> String {
        let delta = value["delta"] as? [String: Any]
        return (value["text"] ?? value["content"] ?? delta?["text"] ?? delta?["thinking"] ?? value["delta"]) as? String ?? ""
    }

    static func hasFinalReply(_ entry: PendingSend) -> Bool {
        guard let bubbles = entry.bubbles else { return !entry.reply.isEmpty }
        return bubbles.last.map { !$0.text.isEmpty && !$0.interim } ?? false
    }

    static func messages(_ entry: PendingSend) -> [Message] {
        let bubbles = entry.bubbles ?? [StreamReply(id: entry.replyID, text: entry.reply)]
        return bubbles.enumerated().map { index, bubble in
            Message(id: bubble.id, role: "being", text: bubble.text, sceneID: entry.sceneID,
                    sequence: bubble.sequence, timestamp: entry.createdAt,
                    localBaseline: entry.baseline, replyTo: entry.userID,
                    localAfter: index == 0 ? entry.userID : bubbles[index - 1].id, streaming: !bubble.closed)
        }
    }

    static func bindHistory(_ confirmed: [Message], to entry: PendingSend) -> [Message] {
        let replies = messages(entry)
        var used = Set<UUID>()
        return confirmed.enumerated().map { index, row in
            var row = row
            // A run belongs to the initiating user turn, not every reply bubble.
            guard row.role == "being" else {
                if row.id == entry.userID { row.process = entry.process }
                return row
            }
            let available = replies.filter { !used.contains($0.id) }
            let match = available.first { $0.sequence != nil && $0.sequence == row.sequence }
                ?? available.first { $0.sequence == nil && $0.text == row.text }
                ?? (index == confirmed.count - 1 ? available.last(where: { $0.sequence == nil }) : nil)
            if let match { row.id = match.id; used.insert(match.id) }
            row.streaming = false
            row.replyTo = entry.userID
            return row
        }
    }
}
