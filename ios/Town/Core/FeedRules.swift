import Foundation
public enum FeedRules {
    public static func newestFirst(_ rows: [[String:Any]]) -> [[String:Any]] {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        let ranked = rows.enumerated().map { index,row in
            let raw = (row["at"] as? String) ?? (row["created_at"] as? String) ?? ""
            let date = fractional.date(from:raw) ?? standard.date(from:raw)
            let seq = (row["seq"] as? NSNumber)?.intValue ?? Int(row["seq"] as? String ?? "") ?? 0
            return (row:row,time:date?.timeIntervalSince1970 ?? 0,seq:seq,index:index)
        }
        return ranked.sorted { a,b in
            if a.time != b.time { return a.time > b.time }
            if a.seq != b.seq { return a.seq > b.seq }
            return a.index > b.index
        }.map(\.row)
    }
    public static func announcementQuery(category:String,includeExpired:Bool) -> [URLQueryItem] {
        var query = [URLQueryItem(name:"include_expired",value:includeExpired ? "true" : "false")]
        if !category.isEmpty { query.append(URLQueryItem(name:"category",value:category)) }
        return query
    }
}

public struct FeedFilter {
    public var author = ""
    public var relation = "all"
    public var days = 0
    public var oldestFirst = false
    public init() {}
    public func matches(_ row: [String: Any], me: String, now: Date = Date()) -> Bool {
        func pick(_ keys: [String]) -> String { keys.compactMap { row[$0] as? String }.first { !$0.isEmpty } ?? "" }
        let authorID = pick(["sender_town_id", "sender_being_id", "sender_id", "town_id", "being_id", "being", "sender"])
        let name = pick(["sender_display", "sender_display_name", "speaker_name", "display_name", "display", "sender_name"])
        if !author.isEmpty && !authorID.localizedCaseInsensitiveContains(author) && !name.localizedCaseInsensitiveContains(author) { return false }
        let mine = !me.isEmpty && authorID == me
        let received = !me.isEmpty && pick(["recipient_town_id", "recipient_being_id", "recipient_id", "recipient", "to"]) == me
        let content = pick(["content", "message"])
        let regex = try! NSRegularExpression(pattern: "@([A-Za-z0-9_-]+)")
        let tokens = regex.matches(in: content, range: NSRange(content.startIndex..., in: content)).compactMap { Range($0.range(at: 1), in: content).map { String(content[$0]) } }
        let mentions = (row["mentions"] as? [Any])?.compactMap { value in (value as? String) ?? (value as? [String: Any])?["town_id"] as? String ?? (value as? [String: Any])?["being_id"] as? String } ?? tokens
        let mentioned = !me.isEmpty && mentions.contains(me)
        if relation == "mine" && !mine || relation == "mentions" && !mentioned || relation == "about" && !(mine || received || mentioned) { return false }
        if days > 0 {
            let raw = pick(["at", "created_at"])
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw), date >= now.addingTimeInterval(-Double(days) * 86400) else { return false }
        }
        return true
    }
}
