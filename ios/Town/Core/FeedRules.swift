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
