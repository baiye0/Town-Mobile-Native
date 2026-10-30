import Foundation
import SwiftUI

struct IOSPortalAction: Codable, Identifiable {
    var id: String
    var tool: String
    var arguments: Data
    var fingerprint: String
    var created = Date()
    var state = "completed"
    var result: Data?
    var preview: [String: String]?
    var summary: String { "\(tool.replacingOccurrences(of: "portal_ios_", with: "")) · \((try? JSONSerialization.jsonObject(with: arguments) as? [String: Any])?["action"] as? String ?? "")" }
}
struct IOSPortalActivity: Codable, Identifiable, Sendable {
    var id = UUID()
    var time = Date()
    let tool: String
    var status: String
}

@MainActor final class IOSPortalStore: ObservableObject {
    static let shared = IOSPortalStore()
    @Published private(set) var phase = "stopped"
    @Published var notice: String?
    @Published private(set) var options = LocalPortalOptions()
    @Published private(set) var actions: [IOSPortalAction] = []
    @Published private(set) var activity: [IOSPortalActivity] = []
    @Published private(set) var connection: Connection?
    @Published var permissionRevision = 0
    let native = IOSPortalNative()
    let health: IOSPortalHealthAccess
    private let injectedPermissions: IOSPortalPermissions?
    var permissions: IOSPortalPermissions { injectedPermissions ?? native }
    @Published private(set) var authorizing: String?
    @Published private(set) var healthRequesting = false
    private var healthAttempt = UUID()
    var healthGeneration = UUID()
    var fileGeneration = UUID()
    private var permissionAttempt = UUID()
    private var ownerEpoch = UUID()
    let base: URL
    private var storageReady = false
    private let activityQueue = DispatchQueue(label: "town.portal.activity", qos: .utility)
    private var activitySnapshots: [String: [IOSPortalActivity]] = [:]
    var runner: Task<Void, Never>?
    var socket: URLSessionWebSocketTask?
    var session: URLSession?
    var calls: [UUID: Task<Void, Never>] = [:]
    var generation = UUID()
    var wanted = false
    var lastSeen = Date()
    var workspace: LocalPortalWorkspace? {
        guard let connection, storageReady else { return nil }
        return try? LocalPortalWorkspace(root: base.appendingPathComponent(LocalPortalRules.owner(connection)).appendingPathComponent("workspace"))
    }
    var running: Bool { wanted }
    var status: String {
        ["stopped": "尚未启动", "connecting": "正在连接", "connected": "已连接", "retrying": "连接中断，正在重试", "paused": "后台已暂停，回到应用后恢复", "invalid": "连接被拒绝，请检查 Being 凭据", "error": "启动失败"][phase] ?? phase
    }
    init(base: URL = URL.applicationSupportDirectory.appendingPathComponent("ios-portal"), permissions: IOSPortalPermissions? = nil, health: IOSPortalHealthAccess? = nil) {
        self.base = base
        injectedPermissions = permissions
        self.health = health ?? IOSPortalHealth()
        native.permissionChanged = { [weak self] in self?.refreshPermissions() }
    }
    func bind(_ value: Connection?) {
        guard connection != value || !storageReady else { return }
        ownerEpoch = UUID(); permissionAttempt = UUID(); healthAttempt = UUID()
        stop(); connection = value; actions = []; activity = []; notice = nil; storageReady = false
        options = LocalPortalOptions()
        guard let value else { return }
        do {
            var home = base.appendingPathComponent(LocalPortalRules.owner(value))
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try home.setResourceValues(flags)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: home.path)
            let config = home.appendingPathComponent("options.json")
            if FileManager.default.fileExists(atPath: config.path) { options = try JSONDecoder().decode(LocalPortalOptions.self, from: Data(contentsOf: config)); try options.validate() }
            let journal = home.appendingPathComponent("actions.json")
            if FileManager.default.fileExists(atPath: journal.path) { actions = try JSONDecoder().decode([IOSPortalAction].self, from: Data(contentsOf: journal)) }
            // A crash during a system write is ambiguous: never silently perform it again.
            for i in actions.indices where actions[i].state == "executing" { actions[i].state = "unknown" }
            // Pending is a legacy state from the old phone-confirmation flow. Keep
            // the record for auditability, but never surface or execute it now that
            // native writes are immediate.
            for i in actions.indices where actions[i].state == "pending" { actions[i].state = "cancelled" }
            storageReady = true
            let log = home.appendingPathComponent("activity.json")
            let saved = activitySnapshots[LocalPortalRules.owner(value)] ?? (try? Data(contentsOf: log)).flatMap { try? JSONDecoder().decode([IOSPortalActivity].self, from: $0) }
            if let saved {
                activity = Array(saved.prefix(100))
                for i in activity.indices where activity[i].status == "执行中" { activity[i].status = "已中断" }
            }
            try persist()
            refreshPermissions()
        } catch { storageReady = false; notice = "Portal 本地配置读取失败，已停止访问。请保留数据并重试。" }
    }
    func persist() throws {
        guard let connection, storageReady else { throw PortalError.server("Portal 本地存储不可用。") }
        let home = base.appendingPathComponent(LocalPortalRules.owner(connection))
        try JSONEncoder().encode(options).write(to: home.appendingPathComponent("options.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try JSONEncoder().encode(actions).write(to: home.appendingPathComponent("actions.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func configure(_ change: (inout LocalPortalOptions) -> Void) {
        let previous = options
        change(&options)
        do {
            try options.validate(); try persist()
            if previous.files != options.files { fileGeneration = UUID() }
            if previous.grants.filter({ $0.hasPrefix("health.") }) != options.grants.filter({ $0.hasPrefix("health.") }) { healthGeneration = UUID() }
            if let socket, phase == "connected" { Task { try? await Self.send(["jsonrpc": "2.0", "method": "notifications/tools/list_changed"], to: socket) } }
        } catch { options = previous; stop(); storageReady = false; notice = "设置保存失败，Portal 已停止。请重新打开此页面后重试。" }
    }
    func effectiveGrant(_ key: String) -> Bool {
        options.grants.contains(key) && permissions.permission(String(key.split(separator: ".")[0])).available
    }
    func setGrant(_ key: String, enabled: Bool) {
        if !enabled {
            permissionAttempt = UUID()
            configure { $0.grants.remove(key) }
            return
        }
        Task { await requestGrant(key) }
    }
    func requestGrant(_ key: String) async {
        guard connection != nil, storageReady, authorizing == nil, !healthRequesting else { return }
        let capability = String(key.split(separator: ".")[0])
        let state = permissions.permission(capability)
        if state.available { configure { $0.grants.insert(key) }; return }
        guard state.canRequest else {
            notice = state.label
            return
        }
        let owner = connection, attempt = UUID()
        permissionAttempt = attempt; authorizing = capability; notice = nil
        defer { authorizing = nil; refreshPermissions() }
        do { try await permissions.authorize(capability) }
        catch { if owner == connection, permissionAttempt == attempt { notice = "未获得系统权限，访问保持关闭。可在系统设置中修改。" } }
        guard owner == connection, permissionAttempt == attempt else { return }
        if permissions.permission(capability).available { configure { $0.grants.insert(key) } }
        else { notice = "未获得系统权限，访问保持关闭。可在系统设置中修改。" }
    }
    func refreshPermissions() {
        permissionRevision += 1
        guard storageReady else { return }
        let revoked = options.grants.filter { key in
            !key.hasPrefix("health.") && !permissions.permission(String(key.split(separator: ".")[0])).available
        }
        if !revoked.isEmpty { configure { $0.grants.subtract(revoked) } }
    }
    var healthLinked: Bool { options.grants.contains { $0.hasPrefix("health.") } }
    @discardableResult func connectHealth() async -> Bool {
        guard !healthRequesting, authorizing == nil else { return false }
        guard connection != nil, storageReady else {
            notice = "请先连接 Being，并重新打开 Portal 页面后重试。"
            return false
        }
        guard health.available else {
            notice = "此设备暂不支持 Apple 健康。"
            return false
        }
        let owner = connection, epoch = ownerEpoch, attempt = UUID()
        healthAttempt = attempt
        healthRequesting = true; notice = nil
        defer { healthRequesting = false }
        do {
            let categories = Set(IOSPortalHealth.categories.map(\.id))
            // The user initiates a connection to Apple Health. HealthKit controls
            // which records are shared; a completed sheet is not proof of read access.
            try await health.authorize(categories)
            guard owner == connection, epoch == ownerEpoch, attempt == healthAttempt else { return false }
            configure { $0.grants.formUnion(categories.map { "health." + $0 + ".read" }) }
            return storageReady && healthLinked
        } catch {
            if owner == connection, epoch == ownerEpoch, attempt == healthAttempt {
                notice = "Apple 健康关联未完成，请重试。"
            }
        }
        return false
    }
    func revokeHealthGrants() {
        healthAttempt = UUID()
        configure { $0.grants = $0.grants.filter { !$0.hasPrefix("health.") } }
    }
    func capability(_ tool: String) -> String { tool.replacingOccurrences(of: "portal_ios_", with: "") }
    func check(_ tool: String, write: Bool = false) throws {
        guard storageReady, connection != nil else { throw PortalError.server("请先连接 Being。") }
        guard options.grants.contains(capability(tool) + (write ? ".write" : ".read")) else { throw PortalError.server("当前 Being 未获此项授权。") }
        guard permissions.permission(capability(tool)).available else { throw PortalError.server("系统权限尚未授予，请在手机的 Portal 页面继续授权。") }
    }
    func record(_ tool: String, _ status: String, id: UUID = UUID()) {
        if let index = activity.firstIndex(where: { $0.id == id }) {
            activity[index].status = status
        } else {
            activity.insert(IOSPortalActivity(id: id, tool: tool, status: status), at: 0)
            if activity.count > 100 { activity.removeLast(activity.count - 100) }
        }
        saveActivity()
    }
    private func saveActivity() {
        guard storageReady, let connection else { return }
        let snapshot = activity
        let owner = LocalPortalRules.owner(connection)
        // Rebinding an owner may happen before its queued write reaches disk.
        activitySnapshots[owner] = snapshot
        let url = base.appendingPathComponent(owner).appendingPathComponent("activity.json")
        // Preserve write order without encoding or touching disk on the UI actor.
        activityQueue.async { [weak self] in
            do { try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
            catch { Task { @MainActor in
                guard let self, self.connection == connection else { return }
                self.notice = "最近活动暂未保存，请检查设备存储空间。"
            } }
        }
    }
    func flushActivity() async {
        await withCheckedContinuation { continuation in activityQueue.async { continuation.resume() } }
    }
    func enqueue(_ tool: String, args: [String: Any]) throws -> [String: Any] {
        try check(tool, write: true)
        try native.validateWrite(capability(tool), args)
        // request_id remains optional. Callers that provide it get idempotent
        // retries; ordinary Portal calls execute without having to manufacture
        // an approval token first.
        let id = args["request_id"] == nil ? "ios-" + UUID().uuidString.lowercased() : try LocalPortalRules.string(args, "request_id", max: 128)
        let fingerprint = try LocalPortalRules.fingerprint(tool: tool, arguments: args)
        if let prior = actions.first(where: { $0.id == id }) {
            guard prior.fingerprint == fingerprint else { throw PortalError.server("request_id 已用于不同参数。") }
            return actionResult(prior)
        }
        var item = IOSPortalAction(id: id, tool: tool, arguments: try JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]), fingerprint: fingerprint, preview: try native.preview(capability(tool), args))
        item.state = "executing"
        let previous = actions
        actions.append(item)
        while actions.count > 400, let index = actions.firstIndex(where: { !["executing", "unknown"].contains($0.state) }) { actions.remove(at: index) }
        guard actions.count <= 400 else { actions = previous; throw PortalError.server("操作记录已满。") }
        do { try persist() } catch { actions = previous; throw error }
        guard let index = actions.firstIndex(where: { $0.id == id }) else { throw PortalError.server("操作记录不可用。") }
        do {
            let result = try native.write(capability(tool), args)
            actions[index].result = try JSONSerialization.data(withJSONObject: result)
            actions[index].state = "completed"
            do { try persist() } catch {
                actions[index].state = "unknown"
                try? persist()
                throw error
            }
            return actionResult(actions[index])
        } catch {
            if actions[index].state == "executing" {
                actions[index].state = "unknown"
                try? persist()
            }
            throw error
        }
    }
    func actionResult(_ item: IOSPortalAction) -> [String: Any] {
        var result: [String: Any] = ["request_id": item.id, "status": item.state]
        if let data = item.result, let object = try? JSONSerialization.jsonObject(with: data) { result["result"] = object }
        if item.state == "unknown" { result["message"] = "执行结果待核实，请检查系统记录，勿自动重试。" }
        return result
    }
    func setPhase(_ value: String) { phase = value }
    func suspend() {
        guard wanted else { return }; cancelSession(); phase = "paused"
    }
    func resume() {
        refreshPermissions()
        guard wanted else { return }
        // A suspended socket can still look connected after iOS freezes it.
        // Also bypass an old retry backoff when the user returns to the app.
        if phase == "paused" || phase == "retrying" || runner == nil || Date().timeIntervalSince(lastSeen) > 45 { launch() }
    }
    func stop() { wanted = false; cancelSession(); phase = "stopped" }
    func cancelSession() {
        generation = UUID(); runner?.cancel(); runner = nil
        calls.values.forEach { $0.cancel() }; calls.removeAll()
        interruptActivities()
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        native.cancelLocation()
    }
    func interruptActivities() {
        if activity.contains(where: { $0.status == "执行中" }) {
            for i in activity.indices where activity[i].status == "执行中" { activity[i].status = "已中断" }
            saveActivity()
        }
    }
    func start() {
        guard !wanted, connection != nil, storageReady else { notice = "请先连接 Being，并确认本地配置可用。"; return }
        do { try options.validate(); try persist(); wanted = true; notice = nil; launch() }
        catch { phase = "error"; notice = error.localizedDescription }
    }
}
