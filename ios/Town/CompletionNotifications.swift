import UserNotifications
import SwiftUI

@MainActor final class CompletionNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CompletionNotifications()
    var openScene: ((String, String) -> Void)?
    var pending: (String, String)?
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    func enable() async -> Bool { (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) == true }
    func finished(endpoint: String, scene: String, title: String, shouldNotify: Bool) {
        guard shouldNotify, UserDefaults.standard.bool(forKey: "notify.completed") else { return }
        let content = UNMutableNotificationContent(); content.title = "对话已完成"; content.body = title; content.sound = .default
        content.userInfo = ["endpoint": endpoint, "scene": scene]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    func social(channel: String, title: String, body: String) {
        guard UserDefaults.standard.bool(forKey: "notify.social.enabled"), UserDefaults.standard.bool(forKey: "notify.social.\(channel)") else { return }
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let endpoint = response.notification.request.content.userInfo["endpoint"] as? String
        let scene = response.notification.request.content.userInfo["scene"] as? String
        Task { @MainActor in if let endpoint, let scene { if let openScene { openScene(endpoint, scene) } else { pending = (endpoint, scene) } }; completionHandler() }
    }
}
struct DeliveryQueueView: View {
    @EnvironmentObject private var store: Store
    @State private var edit: String?
    @State private var text = ""
    var body: some View {
        List {
            ForEach(store.visibleOutbox) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title).font(.headline)
                    Text(entry.text.isEmpty ? entry.files.map(\.name).joined(separator: "、") : entry.text).lineLimit(4)
                    Text(["queued": "等待发送", "preparing": "正在准备附件", "sending": "正在回复", "waiting": "服务端排队中", "failed": "发送失败", "unknown": "结果待确认", "stopped": "已停止"][entry.phase] ?? entry.phase).font(.caption)
                    if let error = entry.error { Text(error).font(.caption).foregroundStyle(.red) }
                    if !entry.process.isEmpty { DisclosureGroup("思考与工具过程") { Text(entry.process).font(.caption).textSelection(.enabled) } }
                    if entry.phase == "queued" && store.busy { Button("停止当前回复并优先发送") { Task { await store.interruptQueued(entry.id) } }.font(.caption) }
                    HStack {
                        if DeliveryRules.canEdit(entry.phase) {
                            if entry.files.isEmpty { Button("编辑") { edit = entry.id; text = entry.text } }
                            Button("上移") { store.changeQueued(entry.id, move: -1) }; Button("下移") { store.changeQueued(entry.id, move: 1) }
                            if entry.phase == "failed" { Button("重试") { store.retryQueued(entry.id) } }
                        }
                        if ["queued", "failed", "unknown", "stopped"].contains(entry.phase) { Button("删除", role: .destructive) { store.deleteQueuedMessage(entry) } }
                        if entry.phase == "unknown" { Button("核对结果") { store.resumeDelivery() } }
                    }.buttonStyle(.borderless)
                }.padding(.vertical, 8)
            }
        }.overlay { if store.visibleOutbox.isEmpty { BeingEmptyState("没有等待发送的消息", systemImage: "checkmark.circle") } }.navigationTitle("发送队列")
            .alert("编辑消息", isPresented: Binding(get: { edit != nil }, set: { if !$0 { edit = nil } })) { TextField("消息", text: $text); Button("保存") { if let id = edit { store.changeQueued(id, text: text) }; edit = nil }; Button("取消", role: .cancel) { edit = nil } }
    }
}
