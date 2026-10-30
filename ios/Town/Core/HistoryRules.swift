import Foundation
public enum HistoryRules {
    public static func requestPath(after cursor: Int) -> String {
        cursor > 0 ? "/api/history?limit=500&after=\(cursor)" : "/api/history?limit=500"
    }
    public static func failureMessage(_ error: Error) -> String {
        let detail: String
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: detail = "请求超时，请重试。"
            case .notConnectedToInternet, .networkConnectionLost: detail = "网络连接中断，请联网后重试。"
            default: detail = "网络连接失败（\(error.code.rawValue)），请重试。"
            }
        } else if case PortalError.http(let code) = error {
            detail = code == 401 || code == 403 ? "连接凭据失效或无权限，请重新连接。" : "服务返回 HTTP \(code)，请稍后重试。"
        } else { detail = "服务返回的数据格式不正确，请重试。" }
        return "历史记录读取失败：" + detail
    }

    public static func text(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let blocks = value as? [[String:Any]] { return blocks.compactMap { ($0["text"] ?? $0["content"]) as? String }.joined(separator:"\n\n") }
        return ""
    }
    public static func role(_ raw: String) -> String { raw == "user" ? "user" : "being" }
    public static func marker(_ text: String) -> String {
        if text.lowercased().hasPrefix("[breath yielded") { return "放下手头的事，转向你" }
        if text.lowercased().hasPrefix("[breath interrupted") { return "已停止" }
        if text.lowercased().hasPrefix("[breath superseded") { return "被新的对话取代" }
        return text.trimmingCharacters(in: CharacterSet(charactersIn:"[]"))
    }
}

// Retain locally known sequence rows when the server only returns a partial page.
extension HistoryRules {
    // Streamed replies only grow. A shorter prefix is a stale persistence
    // snapshot; a genuinely different canonical response can still replace it.
    static func replyText(_ incoming: String, preserving received: String) -> String {
        incoming.isEmpty || received.hasPrefix(incoming) ? received : incoming
    }

    static func merge(_ local: [Message], _ confirmed: [Message], activeIDs: Set<UUID> = []) -> [Message] {
        var indexed = Dictionary(local.compactMap { m in m.sequence.map { ($0,m) } }, uniquingKeysWith: { _,new in new })
        for var message in confirmed {
            guard let seq = message.sequence else { continue }
            if let local = indexed[seq] {
                // A history poll can briefly expose an empty placeholder while
                // the stream is still being persisted. Never replace text the
                // client has already received with that placeholder.
                if message.role == "being", message.text.isEmpty || local.replyTo != nil || local.streaming != nil {
                    message.text = replyText(message.text, preserving: local.text)
                }
                message.id = local.id
                message.files = message.files ?? local.files
                message.process = message.process ?? local.process
                message.replyTo = message.replyTo ?? local.replyTo
                message.localAfter = message.localAfter ?? local.localAfter
                if local.streaming == true, message.streaming != false {
                    message.persistedText = message.text
                    message.text = local.text
                    message.streaming = true
                }
            }
            indexed[seq] = message
        }
        let known = Set(local.compactMap(\.sequence))
        var echoes = confirmed.filter { $0.sequence.map { !known.contains($0) } ?? false }.sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
        let attachmentMarker = try! NSRegularExpression(pattern: "(?m)^\\[attachment-message:v1:msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*\\]\\r?$")
        func attachmentLine(_ text: String) -> String? { text.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("[attachment-message:v1:") }).map(String.init) }
        // History can be ahead of the transport. Bind a unique prefix only
        // inside the initiating prompt's turn, never across a later question.
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        func promptStart(_ message: Message) -> Int? {
            guard let promptID = message.replyTo, let prompt = localByID[promptID],
                  let baseline = message.localBaseline else { return nil }
            let matches = confirmed.filter { $0.role == "user" && $0.sceneID == prompt.sceneID &&
                ($0.sequence ?? 0) > baseline && DeliveryRules.matchesSubmittedText($0.text, prompt.text) }
            return prompt.sequence ?? (matches.count == 1 ? matches.first?.sequence : nil)
        }
        func liveEcho(_ message: Message) -> Message? {
            guard let promptID = message.replyTo, let start = promptStart(message) else { return nil }
            let end = indexed.values.filter { $0.role == "user" && $0.sceneID == message.sceneID && ($0.sequence ?? 0) > start }
                .compactMap(\.sequence).min() ?? Int.max
            let previous = message.localAfter.flatMap { localByID[$0]?.sequence } ?? start
            let candidates = indexed.values.filter { row in
                guard row.role == "being", row.kind == nil, row.sceneID == message.sceneID,
                      let seq = row.sequence, seq > max(start, previous), seq < end,
                      row.replyTo == nil || row.id == message.id else { return false }
                return !message.text.isEmpty && !row.text.isEmpty &&
                    (row.text == message.text || message.streaming == true &&
                        (row.text.hasPrefix(message.text) || message.text.hasPrefix(row.text)))
            }
            guard candidates.count == 1, let candidate = candidates.first else { return nil }
            let competing = local.filter { $0.sequence == nil && $0.replyTo == promptID && !$0.text.isEmpty &&
                (candidate.text == $0.text || $0.streaming == true && (candidate.text.hasPrefix($0.text) || $0.text.hasPrefix(candidate.text))) }
            return competing.count == 1 ? candidate : nil
        }
        let pending = local.filter { m in
            guard m.sequence == nil else { return false }
            if role(m.role) == "being" && m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if let remote = liveEcho(m), let seq = remote.sequence {
                var merged = remote
                merged.id = m.id; merged.text = m.text; merged.streaming = m.streaming
                merged.persistedText = m.streaming == true ? remote.persistedText ?? remote.text : nil
                merged.replyTo = m.replyTo; merged.localAfter = m.localAfter; merged.localBaseline = m.localBaseline
                merged.files = m.files ?? remote.files; merged.process = m.process ?? remote.process
                indexed[seq] = merged
                echoes.removeAll { $0.sequence == seq }
                return false
            }
            // A known turn must not fall back to an equal text from another turn.
            if promptStart(m) != nil { return true }
            let hasAttachment = attachmentMarker.firstMatch(in: m.text, range: NSRange(m.text.startIndex..., in: m.text)) != nil
            let candidates = hasAttachment ? confirmed : echoes
            if let matched = candidates.firstIndex(where: { candidate in
                guard role(candidate.role) == role(m.role), candidate.sceneID == m.sceneID,
                      m.localBaseline.map({ $0 < (candidate.sequence ?? 0) }) ?? true else { return false }
                if hasAttachment { return attachmentLine(candidate.text) == attachmentLine(m.text) }
                return DeliveryRules.matchesSubmittedText(candidate.text, m.text)
            }) {
                let row = candidates[matched]
                if let seq = row.sequence, var merged = indexed[seq] {
                    if !known.contains(seq) { merged.id = m.id }
                    merged.files = m.files ?? merged.files
                    merged.process = m.process ?? merged.process
                    merged.replyTo = m.replyTo ?? merged.replyTo
                    merged.localAfter = m.localAfter ?? merged.localAfter
                    if m.streaming == true {
                        merged.streaming = true
                        merged.persistedText = merged.text
                        merged.text = m.text
                    }
                    indexed[seq] = merged
                }
                if !hasAttachment { echoes.remove(at: matched) }
                return false
            }
            // Older clients persisted the concatenation of pre-tool text and
            // the final reply, without a sequence or timestamp. Only reconcile
            // an inactive legacy row with one unique, substantial final suffix.
            // Keep the omitted prefix in the expandable process details.
            if role(m.role) == "being", m.timestamp == nil, m.localBaseline == nil, !activeIDs.contains(m.id) {
                let matches = indexed.values.filter {
                    $0.sceneID == m.sceneID && role($0.role) == "being" && $0.kind == nil &&
                    $0.text.count >= 256 && m.text.count > $0.text.count &&
                    $0.text.count * 2 >= m.text.count && m.text.hasSuffix($0.text)
                }
                if matches.count == 1, let row = matches.first, let seq = row.sequence {
                    let prefix = String(m.text.dropLast(row.text.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let process = [indexed[seq]?.process, m.process, prefix].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                    indexed[seq]?.process = process
                    return false
                }
            }
            return true
        }
        return ordered(Array(indexed.values) + pending)
    }

    static func ordered(_ messages: [Message]) -> [Message] {
        // A streaming reply stays after its own prompt when history assigns
        // that prompt a server sequence before the reply has been confirmed.
        let parents = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var positions: [UUID: (Int, Int)] = [:]
        func position(_ message: Message, visiting: Set<UUID> = []) -> (Int, Int) {
            if let cached = positions[message.id] { return cached }
            if let sequence = message.sequence { return (sequence, 0) }
            let baseline = message.localBaseline ?? Int.max
            guard !visiting.contains(message.id),
                  let id = message.localAfter ?? message.replyTo, let parent = parents[id],
                  parent.sceneID == message.sceneID else { return (baseline, 1) }
            let preceding = position(parent, visiting: visiting.union([message.id]))
            let result = (max(baseline, preceding.0), preceding.0 >= baseline ? preceding.1 + 1 : 1)
            positions[message.id] = result
            return result
        }
        // Resolve anchors before sorting; the comparator remains a pure ordering.
        for message in messages { positions[message.id] = position(message) }
        return messages.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            let left = positions[a.id]!, right = positions[b.id]!
            if left.0 != right.0 { return left.0 < right.0 }
            if left.1 != right.1 { return left.1 < right.1 }
            if (a.sequence != nil) != (b.sequence != nil) { return a.sequence != nil }
            if a.sequence == nil, let at = a.timestamp, let bt = b.timestamp, at != bt { return at < bt }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

extension HistoryRules {
    static func sbsStatus(_ snapshot: [String: Any]) -> String? {
        guard snapshot["stream_id"] is String, let finished = snapshot["finished"] as? Bool else { return nil }
        guard !finished, let origin = snapshot["origin"] as? String, origin != "human", !origin.isEmpty,
              (snapshot["scene_id"] as? String ?? "").isEmpty else { return "" }
        var phase = origin == "callback" ? "正在执行回调" : "正在思考"
        for event in snapshot["events"] as? [[String: Any]] ?? [] {
            let type = event["event"] as? String ?? ""
            let data = event["data"] as? [String: Any] ?? [:]
            let delta = data["delta"] as? [String: Any] ?? [:]
            if type == "tool_use" || (data["content_block"] as? [String: Any])?["type"] as? String == "tool_use" { phase = "正在执行工具" }
            else if ["thinking", "reasoning", "tool_result"].contains(type) || delta["type"] as? String == "thinking_delta" { phase = "正在思考" }
            else if ["text", "message"].contains(type) || delta["text"] is String { phase = "正在整理回复" }
        }
        return (origin == "callback" ? "SBS 回调 · " : "SBS 活动 · ") + phase
    }
}
