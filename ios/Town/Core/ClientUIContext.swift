import Foundation

/// Hide transport context across desktop/mobile versions without rewriting history.
public enum ClientUIContext {
    public static func strip(_ source: String, capabilitiesOnly: Bool = false) -> String {
        let text = source.replacingOccurrences(of: "\r\n", with: "\n")
        let names = capabilitiesOnly ? ["客户端 Intelligent UI Beta 上下文"] :
            ["客户端 Intelligent UI Beta 上下文", "客户端当前界面选择", "客户端界面操作"]
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var index = 0, fence: String?
        while index < lines.count {
            let line = lines[index], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(while: { $0 == trimmed.first! }))
                if let current = fence { if marker.first == current.first && marker.count >= current.count { fence = nil } }
                else { fence = marker }
            }
            if fence == nil, let name = names.first(where: { trimmed == "[\($0)]" }),
               let end = lines[(index + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[/\(name)]" }) {
                while result.last == "" { result.removeLast() }
                index = end + 1
                if index < lines.count && !lines[index].isEmpty && !result.isEmpty { result.append("") }
                continue
            }
            result.append(line); index += 1
        }
        return result.joined(separator: "\n")
    }
}
