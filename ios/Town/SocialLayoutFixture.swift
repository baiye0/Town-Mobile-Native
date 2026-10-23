#if DEBUG && targetEnvironment(simulator)
import Foundation

// Opt-in, in-memory UI fixture. Never saves an identity or sends requests to Town.
enum SocialLayoutFixture {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--social-layout-fixture") }
    static let identity = TownIdentity(token: "layout-fixture-only", id: "t_layout", name: "布局预览")
    static func response(_ path: String, body: [String: Any]?) throws -> [String: Any] {
        guard body == nil else { throw PortalError.server("布局预览不发送消息。") }
        let now = ISO8601DateFormatter().string(from: Date())
        if path.hasPrefix("/api/announcements?") {
            return ["items": [["id": "layout-announcement", "title": "小镇的新一天：在这里分享发现与灵感", "pinned": true],
                              ["id": "layout-update", "title": "本周小镇更新", "pinned": false]]]
        }
        if path.hasPrefix("/api/announcements/") { return ["content": "欢迎来到小镇。这里是用于检查布局的示例公告。"] }
        if path.hasPrefix("/api/fireside/list") {
            return ["owned": [["id": "garden", "name": "花园里的慢慢聊", "description": "记录日常里的新发现，分享刚刚冒出来的想法。"],
                              ["id": "reading", "name": "深夜读书会", "description": "一本书，一杯茶，和一些还没聊完的话。"],
                              ["id": "building", "name": "一起做点小东西", "description": "设计、代码与有趣的小实验。"]], "joined": []]
        }
        if path.hasPrefix("/api/fireside/members") { return ["members": [["town_id": "t_layout", "display_name": "布局预览"]]] }
        if path.hasPrefix("/api/messages") {
            if path.contains("with=sent") {
                return ["messages": [["id": "mail-sent", "sender_town_id": "t_layout", "sender_display": "布局预览", "recipient_town_id": "t_lin", "content": "收到，周末一起把这个小想法做出来。", "created_at": now]]]
            }
            return ["messages": [["id": "mail-received", "sender_town_id": "t_lin", "sender_display": "林间", "recipient_town_id": "t_layout", "content": "今天发现了一家安静的小书店。想到上次聊的那个故事，也许我们可以从那里开始。\n\n你最近有什么新想法吗？", "created_at": now]]]
        }
        if path.hasPrefix("/api/bonfire/hear") || path.hasPrefix("/api/fireside/hear") {
            return ["messages": [["id": "post-one", "sender_town_id": "t_lin", "sender_display": "林间", "content": "今天做了一个小实验：把散落的想法整理成一张地图。\n\n发现有些看似不相关的事情，其实一直连在一起。你们通常怎么保存突然冒出来的灵感？", "created_at": now, "seq": 3],
                                  ["id": "post-two", "sender_town_id": "t_yun", "sender_display": "云朵", "content": "我喜欢先写下来，再慢慢整理。\n\n- 一句没写完的话\n- 一张路上的照片\n- 一个值得继续问的问题\n\n留一点空白，让想法有地方生长。", "created_at": now, "seq": 2],
                                  ["id": "post-long", "sender_town_id": "t_layout", "sender_display": "布局预览", "content": String(repeating: "把日常的小发现记下来，也是一种和世界保持联系的方式。\n\n", count: 25), "created_at": now, "seq": 1]]]
        }
        return [:]
    }
}
#endif
