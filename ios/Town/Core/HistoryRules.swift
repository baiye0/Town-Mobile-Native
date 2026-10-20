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
    static func merge(_ local: [Message], _ confirmed: [Message], activeIDs: Set<UUID> = []) -> [Message] {
        var indexed = Dictionary(local.compactMap { m in m.sequence.map { ($0,m) } }, uniquingKeysWith: { _,new in new })
        for var m in confirmed { if let seq = m.sequence { m.id = indexed[seq]?.id ?? m.id; m.files = m.files ?? indexed[seq]?.files; m.process = m.process ?? indexed[seq]?.process; indexed[seq] = m } }
        let known = Set(local.compactMap(\.sequence))
        var echoes = confirmed.filter { $0.sequence.map { !known.contains($0) } ?? false }
        let attachmentMarker = try! NSRegularExpression(pattern: "(?m)^\\[attachment-message:v1:msg_[a-f0-9]{64}(?:,msg_[a-f0-9]{64})*\\]\\r?$")
        func attachmentLine(_ text: String) -> String? { text.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("[attachment-message:v1:") }).map(String.init) }
        let pending = local.filter { m in
            guard m.sequence == nil else { return false }
            if role(m.role) == "being" && m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            let hasAttachment = attachmentMarker.firstMatch(in: m.text, range: NSRange(m.text.startIndex..., in: m.text)) != nil
            let candidates = hasAttachment ? confirmed : echoes
            if let matched = candidates.lastIndex(where: { candidate in
                guard role(candidate.role) == role(m.role), candidate.sceneID == m.sceneID,
                      m.localBaseline.map({ $0 < (candidate.sequence ?? 0) }) ?? true else { return false }
                if hasAttachment { return attachmentLine(candidate.text) == attachmentLine(m.text) }
                return candidate.text == SceneRules.stripTransition(m.text)
            }) {
                let row = candidates[matched]
                if let seq = row.sequence, var merged = indexed[seq] {
                    if !known.contains(seq) { merged.id = m.id }
                    merged.files = m.files ?? merged.files
                    merged.process = m.process ?? merged.process
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
        messages.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            let left = a.sequence ?? a.localBaseline ?? Int.max
            let right = b.sequence ?? b.localBaseline ?? Int.max
            if left != right { return left < right }
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
