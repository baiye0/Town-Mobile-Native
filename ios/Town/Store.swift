import Foundation
import SwiftUI
import Security

final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
enum Vault {
    private static let simulatorFallbackKey = "town.native.connection.simulator"
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "town.native.connection", kSecAttrAccount as String: "being"]
    static func load() -> Connection? {
        var q = query; q[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        #if targetEnvironment(simulator)
        if status == errSecMissingEntitlement { return UserDefaults.standard.data(forKey: simulatorFallbackKey).flatMap { try? JSONDecoder().decode(Connection.self, from: $0) } }
        #endif
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Connection.self, from: data)
    }
    static func save(_ value: Connection?) throws {
        guard let value else {
            SecItemDelete(query as CFDictionary)
            #if targetEnvironment(simulator)
            UserDefaults.standard.removeObject(forKey: simulatorFallbackKey)
            #endif
            return
        }
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(q as CFDictionary, nil)
            #if targetEnvironment(simulator)
            if addStatus == errSecMissingEntitlement { UserDefaults.standard.set(data, forKey: simulatorFallbackKey); return }
            #endif
            guard addStatus == errSecSuccess else { throw PortalError.server("无法保存至钥匙串。") }
            return
        }
        #if targetEnvironment(simulator)
        if status == errSecMissingEntitlement { UserDefaults.standard.set(data, forKey: simulatorFallbackKey); return }
        #endif
        guard status == errSecSuccess else { throw PortalError.server("无法更新钥匙串（\(status)）：\(SecCopyErrorMessageString(status, nil) as String? ?? "")") }
    }
}
@MainActor final class ComposerState: ObservableObject {
    @Published var draft = ""
}

@MainActor final class Store: ObservableObject {
    @Published var connection = Vault.load() { didSet { IOSPortalStore.shared.bind(connection); displayRevision += 1; sbsEnabled = nil; sbsActivity = ""; sbsError = nil; sbsRevision += 1 } }
    @Published var conversations: [Conversation] = [] { didSet { displayRevision += 1 } }
    @Published var selected: String? { didSet { displayRevision += 1; showSBS = UserDefaults.standard.bool(forKey: "scene.sbs.\(connection?.endpoint ?? "")|\(selected ?? "")") } }
    @Published var showAllScenes = false { didSet { displayRevision += 1; if let endpoint = connection?.endpoint { UserDefaults.standard.set(showAllScenes,forKey:"scene.all.\(endpoint)") } } }
    @Published var showSBS = false { didSet { displayRevision += 1 } }
    @Published var timeline: [Message] = [] { didSet { displayRevision += 1 } }
    @Published var historyLoading = false
    private var cachedHistory: [String:[Message]] = [:]
    private var historyFile: URL { URL.documentsDirectory.appending(path:"history-cache.json") }
    @Published var sceneDirectory = UserDefaults.standard.dictionary(forKey: "scene.directory") as? [String:[String]] ?? [:]
    private var mainIDs = UserDefaults.standard.dictionary(forKey: "scene.main") as? [String:String] ?? [:]
    var mainID: String? { connection.flatMap { mainIDs[$0.endpoint] } }
    private var displayRevision = 0
    @Published var messageDeletions: [MessageDeletion] = [] { didSet { displayRevision += 1 } }
    @Published var messageDeletionsUnavailable = false
    private var cachedRevision = -1
    private var cachedDisplay: [Message] = []
    var displayMessages: [Message] {
        let revision = displayRevision
        if cachedRevision != revision { cachedDisplay = buildDisplayMessages().filter { !isMessageDeleted($0, endpoint: connection?.endpoint ?? "") && DeliveryRules.hasVisibleContent($0.text, hasAttachments: $0.files?.isEmpty == false) }; cachedRevision = revision }
        return cachedDisplay
    }
    // Token-only edits do not change row identity or ordering. Patch the visible
    // snapshot instead of re-merging and sorting every historical row per frame.
    func projectConversation(_ room: Conversation, at index: Int) {
        let old = conversations[index].messages
        let cacheWasCurrent = cachedRevision == displayRevision
        conversations[index] = room
        guard cacheWasCurrent, old.count == room.messages.count else { return }
        var updates: [UUID: Message] = [:]
        for (before, after) in zip(old, room.messages) where before != after {
            guard before.id == after.id, before.sequence == after.sequence,
                  before.role == after.role, before.sceneLabel == after.sceneLabel,
                  before.persistedText == after.persistedText,
                  before.text == after.text || after.streaming == true,
                  before.sceneID == after.sceneID, before.replyTo == after.replyTo,
                  before.localAfter == after.localAfter, before.localBaseline == after.localBaseline,
                  before.timestamp == after.timestamp, before.kind == after.kind,
                  before.streaming == after.streaming,
                  DeliveryRules.hasVisibleContent(before.text, hasAttachments: before.files?.isEmpty == false) ==
                    DeliveryRules.hasVisibleContent(after.text, hasAttachments: after.files?.isEmpty == false) else { return }
            updates[after.id] = after
        }
        for i in cachedDisplay.indices {
            guard let update = updates[cachedDisplay[i].id] else { continue }
            // A display-only history merge may already know the server sequence.
            cachedDisplay[i].text = update.text; cachedDisplay[i].process = update.process
            cachedDisplay[i].files = update.files; cachedDisplay[i].streaming = update.streaming
        }
        cachedRevision = displayRevision
    }
    private func buildDisplayMessages() -> [Message] {
        if showAllScenes { return HistoryRules.merge(conversations.filter { $0.endpoint == connection?.endpoint }.flatMap { room in room.messages.map { message in var m = message; if m.sceneID == nil { m.sceneID = room.id }; return m } }, timeline, activeIDs: activeMessageIDs) }
        let messages = current?.messages ?? []
        let shared = showSBS ? timeline.filter { $0.sceneID == nil && $0.role != "user" } : []
        return HistoryRules.ordered(messages + shared)
    }
    private var activeMessageIDs: Set<UUID> {
        Set(visibleOutbox.flatMap { [$0.userID, $0.replyID] + ($0.bubbles ?? []).map(\.id) })
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
    func selectScene(_ id: String) {
        guard rooms.contains(where: { $0.id == id }) else { return }
        let previous = "\(connection?.endpoint ?? "")|\(selected ?? "")"
        sceneUISelections[previous] = intelligentUISelection
        sceneUIModes[previous] = intelligentUI
        sceneDrafts[previous] = draft
        sceneAttachments[previous] = attachments
        selected = id
        let next = "\(connection?.endpoint ?? "")|\(id)"
        intelligentUISelection = sceneUISelections[next]
        // The user may enable UI without a selection, or disable it while
        // retaining a selection. Neither choice can be inferred from the other.
        intelligentUI = sceneUIModes[next] ?? false
        attachments = sceneAttachments[next] ?? []
        draft = sceneDrafts[next] ?? ""
        showSBS = UserDefaults.standard.bool(forKey: "scene.sbs." + next)
    }
    func sceneName(_ message: Message) -> String { guard let id = message.sceneID else { return "全局消息" }; return conversations.first { $0.endpoint == connection?.endpoint && $0.id == id }?.title ?? message.sceneLabel ?? id }
    func saveSBS() { UserDefaults.standard.set(showSBS,forKey:"scene.sbs.\(connection?.endpoint ?? "")|\(selected ?? "")") }
    func createScene(_ name: String, binding id: String? = nil) throws {
        guard let c = connection else { return }
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
    @Published var intelligentUI = false
    @Published var intelligentUISelection: String?
    private var sceneUISelections: [String: String] = [:]
    private var sceneUIModes: [String: Bool] = [:]
    let composer = ComposerState()
    var draft: String {
        get { composer.draft }
        set { composer.draft = newValue }
    }
    private var sceneDrafts: [String:String] = [:]
    private var sceneAttachments: [String:[PendingAttachment]] = [:]
    @Published var busy = false
    @Published var activeScene: String?
    @Published var outbox: [PendingSend] = [] { didSet { displayRevision += 1 } }
    @Published var outboxUnavailable = false
    @Published var submittedMessageID: UUID?
    @Published var streamingReplyID: UUID?
    @Published var attachments: [PendingAttachment] = []
    var appActive = true
    var chatVisible = true
    var worker: Task<Void, Never>?
    var activeSendID: String?
    @Published var connecting = false
    @Published var notice: String?
    @Published var activity = ""
    @Published var sbsEnabled: Bool?
    @Published var sbsUpdating = false
    var sbsRevision = 0
    @Published var sbsError: String?
    @Published var sbsActivity = ""
    var streamID: String?
    var task: Task<Void, Never>?
    let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }()
    private var file: URL { URL.documentsDirectory.appending(path: "conversations.json") }
    var current: Conversation? { conversations.first { $0.id == selected && $0.endpoint == connection?.endpoint } }
    var rooms: [Conversation] { (sceneDirectory[connection?.endpoint ?? ""] ?? []).compactMap { id in conversations.first { $0.id == id && $0.endpoint == connection?.endpoint } } }
    init() {
        if let data = try? Data(contentsOf: file) { conversations = (try? JSONDecoder().decode([Conversation].self, from: data)) ?? [] }
        if let data = try? Data(contentsOf:historyFile) { cachedHistory = (try? JSONDecoder().decode([String:[Message]].self,from:data)) ?? [:] }
        timeline = cachedHistory[connection?.endpoint ?? ""] ?? []
        loadMessageDeletions()
        loadOutbox()
        ensureMain(); selected = mainID
        showSBS = UserDefaults.standard.bool(forKey: "scene.sbs.\(connection?.endpoint ?? "")|\(selected ?? "")")
        showAllScenes = UserDefaults.standard.bool(forKey:"scene.all.\(connection?.endpoint ?? "")")
        if let endpoint = connection?.endpoint { hydrateHistory(endpoint) }
        for entry in visibleOutbox { project(entry) }
    }
    @discardableResult func persist() -> Bool {
        do { try JSONEncoder().encode(conversations).write(to: file, options: [.atomic, .completeFileProtection]); return true }
        catch { notice = "对话未能保存到设备，请检查存储空间。"; return false }
    }
    func newChat() { do { try createScene("新场景") } catch { notice = error.localizedDescription } }
    func request(_ c: Connection, _ path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest {
        var r = URLRequest(url: c.url(path)); r.httpMethod = method; r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if path == "/api/chat/stream" || path.hasPrefix("/api/stream/active") {
            r.cachePolicy = .reloadIgnoringLocalCacheData
            r.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            if path == "/api/chat/stream" { r.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        }
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
            try Vault.save(c); connection = c; showAllScenes = UserDefaults.standard.bool(forKey:"scene.all.\(c.endpoint)"); timeline = cachedHistory[c.endpoint] ?? []; ensureMain(); selected = mainID; draft = ""; attachments = []; intelligentUISelection = nil; intelligentUI = false; hydrateHistory(c.endpoint); notice = nil; return true
        } catch { notice = error is PortalError ? error.localizedDescription : "无法连接，请检查网络和 Being 服务。"; return false }
    }
    func disconnect() { guard !busy else { return }; try? Vault.save(nil); connection = nil; timeline = []; selected = nil; draft = ""; attachments = []; intelligentUISelection = nil; intelligentUI = false }
    func rename(_ id: String, _ text: String) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, SceneRules.validName(title), let i = conversations.firstIndex(where: { $0.id == id && $0.endpoint == connection?.endpoint }) else { return }
        conversations[i].title = String(title.prefix(128)); persist()
    }
    func delete(_ id: String) {
        guard !busy, let endpoint = connection?.endpoint else { return }
        guard !outbox.contains(where: { $0.endpoint == endpoint && $0.sceneID == id }) else { notice = "请先处理该场景的发送队列。"; return }
        sceneDirectory[endpoint]?.removeAll { $0 == id }
        if id == mainID { mainIDs[endpoint] = nil; ensureMain() }
        if selected == id { selected = mainID; intelligentUISelection = nil; intelligentUI = false }; saveDirectory(); persist()
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
            conversations[i].messages = HistoryRules.merge(local, confirmed, activeIDs: activeMessageIDs)
        }
    }
    func history() async {
        guard !historyLoading, let c = connection else { return }
        historyLoading = true; defer { historyLoading = false }
        var cached = cachedHistory[c.endpoint] ?? []
        var cursor = cached.compactMap(\.sequence).max() ?? 0
        if timeline != cached { timeline = cached; hydrateHistory(c.endpoint) }
        let initial = cursor == 0
        if notice?.hasPrefix("历史记录") == true { notice = nil }
        do {
            while !Task.isCancelled {
                let result = try await json(c, HistoryRules.requestPath(after: cursor))
                try Task.checkCancellation(); guard connection == c else { return }
                guard let page = result["messages"] as? [[String:Any]] else { throw PortalError.invalidResponse }
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
                do {
                    try JSONEncoder().encode(cachedHistory).write(to:historyFile,options:[.atomic,.completeFileProtection])
                } catch { notice = "历史记录已加载，但缓存保存失败，请检查设备存储空间或解锁后重试。" }
                persist()
                if initial { break }
            }
            if notice == "发送未完成，请查看发送队列。" { notice = nil }
        } catch is CancellationError { }
        catch { if !Task.isCancelled, connection == c, (error as? URLError)?.code != .cancelled { notice = HistoryRules.failureMessage(error) } }
    }
    func stop() async {
        guard let c = connection, let streamID else { notice = "正在等待服务确认，稍后可停止。"; return }
        let activeTask = worker
        let scene = activeScene
        let entryID = activeSendID
        do {
            let (_, response) = try await session.data(for: request(c, "/api/stop", method: "POST", body: ["stream_id": streamID]))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PortalError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
            guard self.streamID == streamID, activeScene == scene else { return }
            activeTask?.cancel()
            if let i = outbox.firstIndex(where: { $0.id == entryID }) { outbox[i].phase = "stopped"; try? saveOutbox() }
            notice = nil
        }
        catch { notice = "停止请求失败，Being 可能仍在运行。" }
    }
}

extension Store {
    var sbsStatus: String { !sbsActivity.isEmpty ? sbsActivity : sbsEnabled.map { $0 ? "SBS 待命中" : "SBS 已关闭" } ?? "SBS 状态待同步" }
    func syncSBS() async {
        guard let c = connection else { return }
        let revision = sbsRevision
        if let config = try? await json(c, "/api/llm/config"), connection == c, !Task.isCancelled,
           revision == sbsRevision, !sbsUpdating, let enabled = config["sbs_enabled"] as? Bool { sbsEnabled = enabled }
        guard connection == c, !Task.isCancelled else { return }
        do {
            let (bytes, response) = try await session.data(for: request(c, "/api/stream/active"))
            guard connection == c, !Task.isCancelled else { return }
            if (response as? HTTPURLResponse)?.statusCode == 204 { sbsActivity = "" }
            else if (response as? HTTPURLResponse)?.statusCode == 200,
                    let snapshot = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                    let status = HistoryRules.sbsStatus(snapshot) { sbsActivity = status }
            if showSBS || showAllScenes { await history() }
        } catch { /* Keep the last confirmed state; the foreground loop retries. */ }
    }
    func setSBSEnabled(_ enabled: Bool) async {
        guard let c = connection, sbsEnabled != nil, !sbsUpdating else { return }
        sbsUpdating = true; sbsRevision += 1
        defer { sbsUpdating = false }
        do {
            let result = try await json(c, "/api/llm/config", method: "PATCH", body: ["sbs_enabled": enabled ? "on" : "off"])
            guard connection == c else { return }
            guard result["ok"] as? Bool == true, let value = (result["config"] as? [String: Any])?["sbs_enabled"] as? Bool else { throw PortalError.invalidResponse }
            sbsEnabled = value; sbsError = nil
        } catch { if connection == c { sbsError = "SBS 设置未保存，请重试。" } }
    }
}
