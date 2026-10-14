import Foundation
public struct PairCodeCollector {
    private var reply = ""
    public private(set) var eventTypes: Set<String> = []
    public private(set) var textLength = 0
    public private(set) var ignoredScenes = 0
    private let sceneID: String
    public init(sceneID: String) { self.sceneID = sceneID }
    public mutating func consume(_ event: SSEEvent) throws -> String? {
        if event.data == "[DONE]" { return try finish() }
        guard let data = event.data.data(using: .utf8), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PortalError.server("Being 回复格式无效，请使用手动配对。") }
        if let scene = value["scene_id"] as? String, scene != sceneID { ignoredScenes += 1; return nil }
        let type = event.name == "message" ? (value["type"] as? String ?? "message") : event.name
        eventTypes.insert(type)
        if type == "error" { throw PortalError.server("Being 未能完成配对请求，请使用手动配对。") }
        if ["done", "end"].contains(type) { return try finish() }
        if type == "content_block_delta", let delta = value["delta"] as? [String: Any], delta["type"] == nil || delta["type"] as? String == "text_delta", let text = delta["text"] as? String { reply += text }
        else if ["text", "message"].contains(type), let text = (value["text"] ?? value["content"]) as? String { reply += text }
        textLength = max(textLength, reply.utf16.count)
        if reply.utf16.count > 8192 { throw PortalError.server("Being 未返回明确的配对码，请使用手动配对。") }
        if type == "message_stop" {
            defer { reply = "" }
            return try finish()
        }
        return nil
    }
    public func finish() throws -> String? {
        let regex = try NSRegularExpression(pattern: "(?<![A-Za-z0-9])[A-Z0-9]{6}(?![A-Za-z0-9])")
        let codes = Set(regex.matches(in: reply, range: NSRange(reply.startIndex..., in: reply)).compactMap { Range($0.range, in: reply).map { String(reply[$0]) } })
        guard codes.count <= 1 else { throw PortalError.server("未收到唯一的 6 位配对码，请使用手动配对。") }
        return codes.first
    }
}
public enum TownContracts {
    public static func identity(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = value.hasPrefix("t_") ? value : value.lowercased()
        guard id.range(of:"^(t_[A-Za-z0-9_-]{1,62}|[a-z0-9_-]{1,64})$",options:.regularExpression) != nil else { throw PortalError.invalidResponse }
        return id
    }
    public static func validatePair(input: String, townID: String?, beingID: String?, token: String) throws {
        guard token.range(of:"^[A-Za-z0-9._~-]{16,2048}$",options:.regularExpression) != nil else { throw PortalError.invalidResponse }
        if let townID { guard try identity(townID) == townID, townID.hasPrefix("t_") else { throw PortalError.invalidResponse } }
        if input.hasPrefix("t_") { guard let townID, townID.hasPrefix(input) else { throw PortalError.invalidResponse } }
        else if let beingID, beingID != input { throw PortalError.invalidResponse }
    }
}

struct FiresideMember: Identifiable, Equatable {
    let id: String
    let name: String
    let townID: String
    let joinedAt: String
}
extension TownContracts {
    static func members(_ payload: Any) throws -> [FiresideMember] {
        guard let values = (payload as? [Any]) ?? (payload as? [String: Any])?["members"] as? [Any] else {
            throw PortalError.server("Town 返回的成员名单格式不正确。")
        }
        var seen = Set<String>()
        return values.compactMap { value in
            let record = value as? [String: Any] ?? [:]
            func pick(_ keys: [String]) -> String {
                for key in keys {
                    if let text = record[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
                    if let number = record[key] as? NSNumber { return number.stringValue }
                }
                return ""
            }
            let townID = pick(["town_id", "being_id", "id"])
            let name = record.isEmpty ? ((value as? String) ?? (value as? NSNumber)?.stringValue ?? "") : pick(["display_name", "displayName", "name", "display", "town_id", "being_id", "id"])
            let id = townID.isEmpty ? name : townID
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, seen.insert(id).inserted else { return nil }
            return FiresideMember(id: id, name: name, townID: townID, joinedAt: pick(["joined_at", "joinedAt"]))
        }
    }
    static func authorKey(_ identity: String) -> String { identity.hasPrefix("t_") ? "author" : "being_id" }
}
