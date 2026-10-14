import Foundation
public enum HistoryRules {
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
    static func merge(_ local: [Message], _ confirmed: [Message]) -> [Message] {
        var indexed = Dictionary(local.compactMap { m in m.sequence.map { ($0,m) } }, uniquingKeysWith: { _,new in new })
        for m in confirmed { if let seq = m.sequence { indexed[seq] = m } }
        let known = Set(local.compactMap(\.sequence))
        var echoes = confirmed.filter { $0.sequence.map { !known.contains($0) } ?? false }
        let pending = local.filter { m in
            guard m.sequence == nil else { return false }
            if role(m.role) == "being" && m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if let i = echoes.firstIndex(where: { role($0.role) == role(m.role) && $0.text == SceneRules.stripTransition(m.text) && $0.sceneID == m.sceneID }) {
                echoes.remove(at:i); return false
            }
            return true
        }
        return indexed.values.sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) } + pending
    }
}
