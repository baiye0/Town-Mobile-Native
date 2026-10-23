import Foundation
import SwiftUI
import Security

struct TownIdentity: Codable, Equatable { let token: String; let id: String; let name: String }
enum TownVault {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "beings.native.town", kSecAttrAccount as String: "identity"]
    static func load() -> TownIdentity? { var q = query; q[kSecReturnData as String] = true; var result: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }; return try? JSONDecoder().decode(TownIdentity.self, from: data) }
    static func save(_ identity: TownIdentity?) throws {
        guard let identity else { SecItemDelete(query as CFDictionary); return }
        let data = try JSONEncoder().encode(identity)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound { var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly; guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw PortalError.server("身份保存失败。") } }
        else if result != errSecSuccess { throw PortalError.server("身份保存失败。") }
    }
}
func field(_ record: [String: Any], _ names: String...) -> String {
    for name in names { if let s = record[name] as? String, !s.isEmpty { return s }; if let n = record[name] as? NSNumber { return n.stringValue } }; return ""
}
@MainActor final class SocialStore: ObservableObject {
    @Published var identity = TownVault.load()
    @Published var status = "尚未配对"
    @Published var revision = 0
    @Published var counts: [String: Int] = [:]
    var seen: Set<String> = []
    private var live: Task<Void, Never>?
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    init() {
        #if DEBUG && targetEnvironment(simulator)
        if SocialLayoutFixture.enabled { identity = SocialLayoutFixture.identity; status = "布局预览" }
        #endif
    }
    func unread(_ destination: Destination) -> Int { counts[destination.rawValue] ?? 0 }
    func acknowledge(_ kind: Destination) { counts[kind.rawValue] = 0 }
    func request(_ path: String, privateRoute: Bool = true, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard path.hasPrefix("/api") else { throw PortalError.invalidResponse }
        #if DEBUG && targetEnvironment(simulator)
        if SocialLayoutFixture.enabled { return try SocialLayoutFixture.response(path, body: body) }
        #endif
        let credential = identity
        if privateRoute && credential == nil { throw PortalError.server("请先配对小镇身份。") }
        var req = URLRequest(url: URL(string: "https://beings.town" + path)!); req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if privateRoute, let credential { req.setValue("Bearer " + credential.token, forHTTPHeaderField: "Authorization") }
        if let body { req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: req)
        if privateRoute && credential != identity { throw CancellationError() }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if path == "/api/client/pair/confirm" { throw PortalError.server(status == 429 ? "配对尝试过于频繁，请稍后重试。" : "配对失败（HTTP \(status)），请核对 Town ID 或 Being 名与配对码。") }
            throw PortalError.server(status == 401 ? "Town 凭据无效或已失效，请重新配对。" : status == 403 ? "当前 Being 无权访问此内容或执行此操作。" : "Town 请求失败（HTTP \(status)）。")
        }
        guard data.count <= 4 * 1024 * 1024 else { throw PortalError.server("内容过大，请减少读取数量。") }
        let result = try JSONSerialization.jsonObject(with: data)
        if path.hasPrefix("/api/fireside/members"), let values = result as? [Any] { return ["members": values] }
        guard let value = result as? [String: Any] else { throw PortalError.invalidResponse }; return value
    }
    func pair(_ rawID: String, _ rawCode: String) async throws {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = trimmed.hasPrefix("t_") ? trimmed : trimmed.lowercased()
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard id.range(of: "^(t_[A-Za-z0-9_-]{1,62}|[a-z0-9_-]{1,64})$", options: .regularExpression) != nil,
              code.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil else { throw PortalError.server("请输入 Town ID 或 Being 名，以及配对码。") }
        let data = try await request("/api/client/pair/confirm", privateRoute: false, body: [id.hasPrefix("t_") ? "town_id" : "being_id": id, "code": code])
        guard data["ok"] as? Bool == true, let token = data["token"] as? String, token.range(of: "^[A-Za-z0-9._~-]{16,2048}$", options: .regularExpression) != nil else { throw PortalError.invalidResponse }
        try TownContracts.validatePair(input: id, townID: data["town_id"] as? String, beingID: data["being_id"] as? String, token: token)
        let returned = field(data, "town_id", "being_id")
        let value = TownIdentity(token: token, id: returned.isEmpty ? id : returned, name: field(data, "display_name", "speaker_name", "display"))
        try Task.checkCancellation(); try TownVault.save(value); identity = value; counts = [:]; seen = []; revision += 1; startLive()
    }
    func unpair() { stopLive(); try? TownVault.save(nil); identity = nil; counts = [:]; seen = []; status = "尚未配对"; revision += 1 }
    func stopLive() { live?.cancel(); live = nil }
    func startLive() {
        #if DEBUG && targetEnvironment(simulator)
        if SocialLayoutFixture.enabled { return }
        #endif
        stopLive(); guard let credential = identity else { return }
        live = Task {
            var attempts = 0
            while !Task.isCancelled && identity == credential {
                do {
                    status = "正在连接小镇…"
                    var c = URLComponents(string: "https://beings.town/api/client/stream")!; c.queryItems = [URLQueryItem(name: "token", value: credential.token)]
                    var req = URLRequest(url: c.url!); req.setValue("text/event-stream", forHTTPHeaderField: "Accept"); req.timeoutInterval = 60
                    let (bytes, response) = try await session.bytes(for: req)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if [401,403].contains(code) { status = "配对已失效，请重新配对"; return }
                    guard code == 200 else { throw PortalError.http(code) }
                    var parser = SSEByteParser(); var hello = false
                    for try await byte in bytes {
                        try Task.checkCancellation(); guard identity == credential else { return }
                        guard let e = try parser.consume(byte), let data = e.data.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        let eventType = e.name == "message" ? object["type"] as? String ?? "message" : e.name
                        if eventType == "hello" {
                            let returned = field(object, "town_id", "being_id")
                            guard object["anonymous"] as? Bool == false, object["token_kind"] as? String == "client", returned == credential.id || (!credential.id.hasPrefix("t_") && object["being_id"] as? String == credential.id) else { status = "身份校验失败，请重新配对"; return }
                            hello = true; attempts = 0; status = "小镇已连接"; revision += 1; continue
                        }
                        guard hello else { throw PortalError.invalidResponse }
                        let key = eventType + ":" + field(object, "fireside_id") + ":" + field(object, "id", "seq")
                        let channel = ["dm": "mail", "bonfire": "bonfire", "fireside": "firesides"][eventType]
                        if let channel, seen.insert(key).inserted { if seen.count > 5000 { seen = [key] }; if field(object, "sender_town_id", "town_id", "being_id") != credential.id { counts[channel, default: 0] += 1; CompletionNotifications.shared.social(channel: channel, title: ["mail":"收到新私信","firesides":"围炉有新消息","bonfire":"篝火有新消息"][channel] ?? "小镇有新消息", body: "打开 Being 查看最新内容") }; revision += 1 }
                    }
                    throw PortalError.invalidResponse
                } catch { if Task.isCancelled { return }; status = "连接中断，正在重连…"; attempts += 1; try? await Task.sleep(for: .seconds(min(30, 2 * attempts))) }
            }
        }
    }
}

extension Store {
    func pairingCode() async throws -> String {
        guard !busy, let c = connection else { throw PortalError.server("请先连接 Being，并等待当前回复结束。") }
        busy = true; defer { busy = false; startDelivery() }
        let scene = "town-pair-" + UUID().uuidString
        let prompt = "请帮我完成 Town 配对：请现在执行 POST https://beings.town/api/client/pair（不需要任何鉴权 header），把返回 JSON 里的 code 字段（6 位大写字母和数字）原样回复给我。只回复这 6 位 code 本身，不要解释、不要多余文字。"
        var req = request(c, "/api/chat/stream", method: "POST", body: ["message": prompt, "scene_id": scene, "session_id": scene, "scene_meta": ["client": "beings-ios/0.2", "scene_label": "Town 配对"]])
        req.timeoutInterval = 90
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForResource = 90
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var diagnostics: [String:Any] = ["stage":"Being stream", "started":ISO8601DateFormatter().string(from:Date())]
        defer { if let data = try? JSONSerialization.data(withJSONObject:diagnostics,options:.sortedKeys) { try? data.write(to:URL.documentsDirectory.appending(path:"pairing-diagnostics.json"),options:.atomic) } }
        let (bytes, response) = try await session.bytes(for: req)
        diagnostics["http"] = (response as? HTTPURLResponse)?.statusCode
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else { throw PortalError.server("无法通过当前 Being 对话取得配对码，请使用手动配对。") }
        var parser = SSEByteParser(); var collector = PairCodeCollector(sceneID: scene); var bytesRead = 0
        defer { diagnostics["events"] = collector.eventTypes.sorted(); diagnostics["assistantTextLength"] = collector.textLength; diagnostics["ignoredScenes"] = collector.ignoredScenes; diagnostics["bytes"] = bytesRead }
        for try await byte in bytes {
            try Task.checkCancellation(); bytesRead += 1
            guard bytesRead <= 1024 * 1024 else { throw PortalError.invalidResponse }
            if let event = try parser.consume(byte), let code = try collector.consume(event) { diagnostics["result"] = "code-detected"; return code }
        }
        if let pending = parser.finish(), let code = try collector.consume(pending) { diagnostics["result"] = "code-detected-at-eof"; return code }
        if let code = try collector.finish() { diagnostics["result"] = "code-detected-at-eof"; return code }
        diagnostics["result"] = "no-unique-code"
        throw PortalError.server("未收到唯一的 6 位配对码，请使用手动配对。")
    }
}
