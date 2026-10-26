import Foundation
import SwiftUI
import UIKit

struct IOSPortalAction: Codable, Identifiable {
    var id: String
    var tool: String
    var arguments: Data
    var fingerprint: String
    var created = Date()
    var state = "pending"
    var result: Data?
    var preview: [String: String]?
    var summary: String { "\(tool.replacingOccurrences(of: "portal_ios_", with: "")) · \((try? JSONSerialization.jsonObject(with: arguments) as? [String: Any])?["action"] as? String ?? "")" }
}
struct IOSPortalActivity: Identifiable {
    let id = UUID()
    let time = Date()
    let tool: String
    let status: String
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
            storageReady = true
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
            // Revoked authorization also invalidates pending writes.
            for i in actions.indices where actions[i].state == "pending" && !options.grants.contains(capability(actions[i].tool) + ".write") { actions[i].state = "cancelled" }
            try persist()
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
    func record(_ tool: String, _ status: String) {
        activity.insert(IOSPortalActivity(tool: tool, status: status), at: 0)
        activity = Array(activity.prefix(100))
    }
    func enqueue(_ tool: String, args: [String: Any]) throws -> [String: Any] {
        try check(tool, write: true)
        try native.validateWrite(capability(tool), args)
        let id = try LocalPortalRules.string(args, "request_id", max: 128)
        let fingerprint = try LocalPortalRules.fingerprint(tool: tool, arguments: args)
        if let prior = actions.first(where: { $0.id == id }) {
            guard prior.fingerprint == fingerprint else { throw PortalError.server("request_id 已用于不同参数。") }
            return actionResult(prior)
        }
        guard actions.filter({ $0.state == "pending" }).count < 20 else { throw PortalError.server("待确认操作已达上限，请先在手机处理。") }
        let item = IOSPortalAction(id: id, tool: tool, arguments: try JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]), fingerprint: fingerprint, preview: try native.preview(capability(tool), args))
        let previous = actions
        actions.append(item)
        while actions.count > 400, let index = actions.firstIndex(where: { !["pending", "executing", "unknown"].contains($0.state) }) { actions.remove(at: index) }
        guard actions.count <= 400 else { actions = previous; throw PortalError.server("操作记录已满。") }
        do { try persist() } catch { actions = previous; throw error }
        return actionResult(item)
    }
    func actionResult(_ item: IOSPortalAction) -> [String: Any] {
        var result: [String: Any] = ["request_id": item.id, "status": item.state]
        if let data = item.result, let object = try? JSONSerialization.jsonObject(with: data) { result["result"] = object }
        if item.state == "pending" { result["message"] = "等待用户在手机 Portal 确认，尚未执行。" }
        if item.state == "unknown" { result["message"] = "执行结果待核实，请检查系统记录，勿自动重试。" }
        return result
    }
    func decide(_ id: String, approve: Bool) {
        guard let i = actions.firstIndex(where: { $0.id == id && $0.state == "pending" }) else { return }
        do {
            if !approve { actions[i].state = "rejected"; try persist(); return }
            guard UIApplication.shared.applicationState == .active else { throw PortalError.server("请回到应用前台执行。") }
            try check(actions[i].tool, write: true)
            guard Date().timeIntervalSince(actions[i].created) < 86400 else { actions[i].state = "expired"; try persist(); return }
            let args = try JSONSerialization.jsonObject(with: actions[i].arguments) as? [String: Any] ?? [:]
            if let preview = actions[i].preview, preview != (try native.preview(capability(actions[i].tool), args)) {
                actions[i].state = "stale"; try persist()
                throw PortalError.server("系统记录已变化，请让 Being 重新读取并提交新的操作。")
            }
            actions[i].state = "executing"; try persist()
            let result = try native.write(capability(actions[i].tool), args)
            actions[i].result = try JSONSerialization.data(withJSONObject: result)
            actions[i].state = "completed"
            do { try persist() } catch { actions[i].state = "unknown"; throw error }
            record(actions[i].tool, "已完成")
        } catch {
            if actions[i].state == "executing" { actions[i].state = "unknown"; try? persist() }
            notice = error is PortalError ? error.localizedDescription : "操作未确认完成，请检查系统记录。"
            record(actions[i].tool, "未确认完成")
        }
    }
    func setPhase(_ value: String) { phase = value }
    func suspend() {
        guard wanted else { return }; cancelSession(); phase = "paused"
    }
    func resume() {
        refreshPermissions()
        guard wanted, phase == "paused" else { return }; launch()
    }
    func stop() { wanted = false; cancelSession(); phase = "stopped" }
    func cancelSession() {
        generation = UUID(); runner?.cancel(); runner = nil
        calls.values.forEach { $0.cancel() }; calls.removeAll()
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        native.cancelLocation()
    }
    func start() {
        guard !wanted, connection != nil, storageReady else { notice = "请先连接 Being，并确认本地配置可用。"; return }
        do { try options.validate(); try persist(); wanted = true; notice = nil; launch() }
        catch { phase = "error"; notice = error.localizedDescription }
    }
}
