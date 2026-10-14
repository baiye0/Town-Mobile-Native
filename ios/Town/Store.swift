import Foundation
import SwiftUI
import Security

final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
enum Vault {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "town.native.connection", kSecAttrAccount as String: "being"]
    static func load() -> Connection? {
        var q = query; q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Connection.self, from: data)
    }
    static func save(_ value: Connection?) throws {
        guard let value else { SecItemDelete(query as CFDictionary); return }
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw PortalError.server("无法保存至钥匙串。") }; return
        }
        guard status == errSecSuccess else { throw PortalError.server("无法更新钥匙串（\(status)）：\(SecCopyErrorMessageString(status, nil) as String? ?? "")") }
    }
}
@MainActor @Observable final class Store {
    var connection = Vault.load() { didSet { displayRevision += 1 } }
    var conversations: [Conversation] = [] { didSet { displayRevision += 1 } }
    var selected: String? { didSet { displayRevision += 1 } }
    var showAllScenes = false { didSet { displayRevision += 1; if let endpoint = connection?.endpoint { UserDefaults.standard.set(showAllScenes,forKey:"scene.all.\(endpoint)") } } }
    var showSBS = false { didSet { displayRevision += 1 } }
    var timeline: [Message] = [] { didSet { displayRevision += 1 } }
    var historyLoading = false
    private var cachedHistory: [String:[Message]] = [:]
    private var historyFile: URL { URL.documentsDirectory.appending(path:"history-cache.json") }
    var sceneDirectory = UserDefaults.standard.dictionary(forKey: "scene.directory") as? [String:[String]] ?? [:]
    private var mainIDs = UserDefaults.standard.dictionary(forKey: "scene.main") as? [String:String] ?? [:]
    var mainID: String? { connection.flatMap { mainIDs[$0.endpoint] } }
    private var displayRevision = 0
    @ObservationIgnored private var cachedRevision = -1
    @ObservationIgnored private var cachedDisplay: [Message] = []
    var displayMessages: [Message] {
        let revision = displayRevision
        if cachedRevision != revision { cachedDisplay = buildDisplayMessages().filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; cachedRevision = revision }
        return cachedDisplay
    }
    private func buildDisplayMessages() -> [Message] {
        if showAllScenes { return HistoryRules.merge(conversations.filter { $0.endpoint == connection?.endpoint }.flatMap { room in room.messages.map { message in var m = message; if m.sceneID == nil { m.sceneID = room.id }; return m } }, timeline) }
        let messages = current?.messages ?? []
        return showSBS ? (messages + timeline.filter { $0.sceneID == nil && $0.role != "user" }).sorted { ($0.sequence ?? Int.max) < ($1.sequence ?? Int.max) } : messages
    }
    func ensureMain() {
        guard let c = connection else { return }
        if mainIDs[c.endpoint] == nil { mainIDs[c.endpoint] = "mobile-" + UUID().uuidString }
        let id = mainIDs[c.endpoint]!
        if !conversations.contains(where: { $0.endpoint == c.endpoint && $0.id == id }) { conversations.insert(Conversation(id:id,endpoint:c.endpoint,title:"主对话"),at:0) }
        if sceneDirectory[c.endpoint] == nil { sceneDirectory[c.endpoint] = conversations.filter { $0.endpoint == c.endpoint && $0.id.hasPrefix("mobile-") }.map(\.id) }
        sceneDirectory[c.endpoint] = [id] + (sceneDirectory[c.endpoint] ?? []).filter { $0 != id }
        UserDefaults.standard.set(mainIDs,forKey:"scene.main")
        saveDirectory()
    }
    private func saveDirectory() { UserDefaults.standard.set(sceneDirectory,forKey:"scene.directory") }
    func selectScene(_ id: String) { guard !busy, rooms.contains(where: { $0.id == id }) else { return }; sceneDrafts["\(connection?.endpoint ?? "")|\(selected ?? "")"] = draft; selected = id; draft = sceneDrafts["\(connection?.endpoint ?? "")|\(id)"] ?? ""; showSBS = UserDefaults.standard.bool(forKey: "scene.sbs.\(connection?.endpoint ?? "")|\(id)") }
    func sceneName(_ message: Message) -> String { guard let id = message.sceneID else { return "未标记场景" }; return conversations.first { $0.endpoint == connection?.endpoint && $0.id == id }?.title ?? message.sceneLabel ?? id }
    func saveSBS() { UserDefaults.standard.set(showSBS,forKey:"scene.sbs.\(connection?.endpoint ?? "")|\(selected ?? "")") }
    func createScene(_ name: String, binding id: String? = nil) throws {
        guard let c = connection, !busy else { return }
        guard SceneRules.validName(name) else { throw PortalError.server("场景名称需为 1–128 个字符。") }
        if let id, !SceneRules.validID(id) { throw PortalError.server("场景 ID 需为 1–256 个非空白 ASCII 字符。") }
        guard rooms.count < 500 else { throw PortalError.server("当前 Being 的场景数量已达上限。") }
        let scene = id ?? "mobile-" + UUID().uuidString
        if !(sceneDirectory[c.endpoint] ?? []).contains(scene) {
            if let i = conversations.firstIndex(where: { $0.id == scene && $0.endpoint == c.endpoint }) { conversations[i].title = name.trimmingCharacters(in: .whitespacesAndNewlines) }
            else { conversations.append(Conversation(id:scene,endpoint:c.endpoint,title:name.trimmingCharacters(in: .whitespacesAndNewlines))) }
            sceneDirectory[c.endpoint,default:[]].append(scene)
        }
        saveDirectory(); selectScene(scene); persist()
    }
    var draft = ""
    private var sceneDrafts: [String:String] = [:]
    var busy = false
    var connecting = false
    var notice: String?
    var activity = ""
    var streamID: String?
    var task: Task<Void, Never>?
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    private var file: URL { URL.documentsDirectory.appending(path: "conversations.json") }
    var current: Conversation? { conversations.first { $0.id == selected && $0.endpoint == connection?.endpoint } }
    var rooms: [Conversation] { (sceneDirectory[connection?.endpoint ?? ""] ?? []).compactMap { id in conversations.first { $0.id == id && $0.endpoint == connection?.endpoint } } }
    init() {
        if let data = try? Data(contentsOf: file) { conversations = (try? JSONDecoder().decode([Conversation].self, from: data)) ?? [] }
        if let data = try? Data(contentsOf:historyFile) { cachedHistory = (try? JSONDecoder().decode([String:[Message]].self,from:data)) ?? [:] }
        timeline = cachedHistory[connection?.endpoint ?? ""] ?? []
        ensureMain(); selected = mainID
        showAllScenes = UserDefaults.standard.bool(forKey:"scene.all.\(connection?.endpoint ?? "")")
        if let endpoint = connection?.endpoint { hydrateHistory(endpoint) }
    }
    func persist() {
        do { try JSONEncoder().encode(conversations).write(to: file, options: [.atomic, .completeFileProtection]) }
        catch { notice = "对话未能保存到设备，请检查存储空间。" }
    }
    func newChat() { do { try createScene("新场景") } catch { notice = error.localizedDescription } }
    func request(_ c: Connection, _ path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest {
        var r = URLRequest(url: c.url(path)); r.httpMethod = method; r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if path.hasPrefix("/api/llm/") { r.setValue(c.secret, forHTTPHeaderField: "X-Relay-Secret") }
        if let body { r.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return r
    }
    func json(_ c: Connection, _ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request(c, path, method: method, body: body))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PortalError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PortalError.invalidResponse }
        return result
    }
    func connect(_ link: String) async -> Bool {
        guard !busy, !connecting else { return false }
        connecting = true
        defer { connecting = false }
        do {
            let c = try Connection(link); _ = try await json(c, "/api/status")
            try Vault.save(c); connection = c; showAllScenes = UserDefaults.standard.bool(forKey:"scene.all.\(c.endpoint)"); timeline = cachedHistory[c.endpoint] ?? []; ensureMain(); selected = mainID; draft = ""; hydrateHistory(c.endpoint); notice = nil; return true
        } catch { notice = error is PortalError ? error.localizedDescription : "无法连接，请检查网络和 Being 服务。"; return false }
    }
    func disconnect() { guard !busy else { return }; try? Vault.save(nil); connection = nil; timeline = []; selected = nil; draft = "" }
    func rename(_ id: String, _ text: String) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, SceneRules.validName(title), let i = conversations.firstIndex(where: { $0.id == id && $0.endpoint == connection?.endpoint }) else { return }
        conversations[i].title = String(title.prefix(128)); persist()
    }
    func delete(_ id: String) {
        guard !busy, let endpoint = connection?.endpoint else { return }
        sceneDirectory[endpoint]?.removeAll { $0 == id }
        if id == mainID { mainIDs[endpoint] = nil; ensureMain() }
        if selected == id { selected = mainID }; saveDirectory(); persist()
    }
    private func hydrateHistory(_ endpoint: String) {
        for message in timeline {
            guard let scene = message.sceneID else { continue }
            if !conversations.contains(where: { $0.id == scene && $0.endpoint == endpoint }) { conversations.append(Conversation(id:scene,endpoint:endpoint,title:message.sceneLabel ?? scene)) }
        }
        for i in conversations.indices where conversations[i].endpoint == endpoint {
            let id = conversations[i].id
            let confirmed = timeline.filter { $0.sceneID == id }
            let local = conversations[i].messages.map { message in var m = message; if m.sceneID == nil { m.sceneID = id }; return m }
            conversations[i].messages = HistoryRules.merge(local, confirmed)
        }
    }
    func history() async {
        guard !busy, !historyLoading, let c = connection else { return }
        historyLoading = true; defer { historyLoading = false }
        var cached = cachedHistory[c.endpoint] ?? []
        var cursor = cached.compactMap(\.sequence).max() ?? 0
        timeline = cached; hydrateHistory(c.endpoint)
        do {
            while !Task.isCancelled {
                let result = try await json(c,"/api/history?limit=500&after=\(cursor)")
                try Task.checkCancellation(); guard connection == c, !busy else { return }
                let page = result["messages"] as? [[String:Any]] ?? []
                let fresh = page.filter { ($0["seq"] as? Int ?? 0) > cursor }
                guard !fresh.isEmpty else { break }
                let incoming = fresh.map { record -> Message in
                    let marker = record["from"] as? String == "system" || record["type"] as? String == "marker"
                    let content = HistoryRules.text(record["content"])
                    let scene = (record["scene_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    return Message(role:HistoryRules.role(record["role"] as? String ?? ""),text:marker ? HistoryRules.marker(content) : SceneRules.stripTransition(content),sceneID:scene,sequence:record["seq"] as? Int,kind:marker ? "marker" : nil,timestamp:record["at"] as? String,sceneLabel:(record["scene_label"] as? String) ?? (record["scene_meta"] as? [String:Any])?["scene_label"] as? String)
                }
                var bySeq = Dictionary(cached.compactMap { m in m.sequence.map { ($0,m) } },uniquingKeysWith: { _,new in new })
                for message in incoming { if let seq = message.sequence { bySeq[seq] = message } }
                cached = bySeq.values.sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
                cursor = fresh.compactMap( { $0["seq"] as? Int } ).max() ?? cursor
                cachedHistory[c.endpoint] = cached; timeline = cached
                hydrateHistory(c.endpoint)
                try JSONEncoder().encode(cachedHistory).write(to:historyFile,options:[.atomic,.completeFileProtection]); persist()
            }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { notice = "历史记录读取失败" } }
    }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, let c = connection else { return }
        if current == nil { newChat() }
        guard let id = selected, let i = conversations.firstIndex(where: { $0.id == id && $0.endpoint == c.endpoint }) else { return }
        draft = ""; busy = true; notice = nil; streamID = nil; activity = "思考中"
        conversations[i].messages.append(Message(role: "user", text: text, sceneID:id)); conversations[i].messages.append(Message(role: "being", text: "", sceneID:id)); conversations[i].updated = Date(); persist()
        task = Task {
            defer { conversations[i].messages.removeAll { $0.sequence == nil && $0.role == "being" && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; busy = false; activity = ""; streamID = nil; persist() }
            do {
                let r = request(c, "/api/chat/stream", method: "POST", body: ["message": text, "scene_id": id, "scene_meta": ["client": "town-ios/0.1", "scene_label": conversations[i].title]])
                let (bytes, response) = try await session.bytes(for: r)
                guard let h = response as? HTTPURLResponse, h.statusCode == 200, h.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else { throw PortalError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
                var parser = SSEByteParser()
                var completed = false
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard let event = try parser.consume(byte) else { continue }
                    if event.data == "[DONE]" { completed = true; break }
                    guard let data = event.data.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    let eventType = event.name == "message" ? object["type"] as? String ?? "message" : event.name
                    if let scene = object["scene_id"] as? String, scene != id { continue }
                    switch eventType {
                    case "meta": streamID = object["stream_id"] as? String ?? streamID
                    case "content_block_delta":
                        completed = false
                        if let delta = object["delta"] as? [String: Any], let text = delta["text"] as? String { conversations[i].messages[conversations[i].messages.count - 1].text += text; activity = "正在回复" }
                    case "text", "message":
                        if let text = (object["text"] ?? object["content"]) as? String { completed = false; conversations[i].messages[conversations[i].messages.count - 1].text += text; activity = "正在回复" }
                    case "done", "end": completed = true
                    case "thinking", "reasoning": activity = "思考中"
                    case "tool_use": activity = "正在使用 \(object["name"] as? String ?? "工具")"
                    case "tool_result": activity = "思考中"
                    case "message_stop": completed = true
                    case "error": throw PortalError.server("Being 返回错误，请稍后重试。")
                    default: break
                    }
                }
                if !completed { throw PortalError.invalidResponse }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { notice = "回复中断，已保留收到的内容。请同步历史后再试。" } }
        }
    }
    func stop() async {
        guard let c = connection, let streamID else { notice = "正在等待服务确认，稍后可停止。"; return }
        let activeTask = task
        do {
            let (_, response) = try await session.data(for: request(c, "/api/stop", method: "POST", body: ["stream_id": streamID]))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PortalError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
            activeTask?.cancel()
            notice = nil
        }
        catch { notice = "停止请求失败，Being 可能仍在运行。" }
    }
}
