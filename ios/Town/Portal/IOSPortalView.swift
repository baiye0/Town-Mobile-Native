import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct IOSPortalView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var portal = IOSPortalStore.shared
    @Environment(\.scenePhase) private var phase
    @State private var name = ""
    @State private var importing = false
    @State private var importOwner: Connection?
    @State private var files: [PortalFileRow] = []
    @State private var directory = "."
    @State private var export: PortalExport?
    @State private var exporting = false
    @State private var expanded = false
    @State private var linkingHealth = false
    private let capabilities = [("calendar", "日历", "calendar"), ("reminders", "提醒事项", "checklist"), ("contacts", "通讯录", "person.crop.rectangle"), ("location", "当前位置", "location")]
    var body: some View {
        SettingsPage {
            SettingsSection(title: "本机 Portal", icon: "iphone.gen3.radiowaves.left.and.right") {
                HStack {
                    Circle().fill(portal.phase == "connected" ? Color.green : Color.secondary).frame(width: 9, height: 9)
                    Text(portal.status).font(.subheadline).accessibilityIdentifier("portalStatus")
                    Spacer()
                    if ["connecting", "retrying"].contains(portal.phase) { ProgressView() }
                }
                if let connection = store.connection { LabeledContent("Being", value: connection.being) }
                else { SettingsNote(text: "连接 Being 后，可让它使用这台设备的工作区和已授权能力。") }
                TextField("设备名", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled().settingsInput().disabled(portal.running)
                    .accessibilityIdentifier("portalName")
                Button(portal.running ? "停止 Portal" : "启动 Portal") {
                    if portal.running { portal.stop() }
                    else { portal.configure { $0.name = name }; if portal.options.name == name { portal.start() } }
                }.buttonStyle(SettingsActionStyle()).disabled(store.connection == nil).accessibilityIdentifier("portalStartStop")
                SettingsNote(text: "Portal 在应用前台运行。切到后台后暂停，回到应用会恢复；关闭应用后需重新启动。切换 Being 会停止连接。")
                if let notice = portal.notice { Text(notice).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
            }
            SettingsSection(title: "手机原生能力", icon: "hand.raised") {
                SettingsNote(text: "按当前 Being 单独授权。读取结果会交给 Being；日历、提醒和联系人写入在获得授权后直接执行。系统权限与 Being 授权分别生效。")
                VStack(alignment: .leading, spacing: 0) {
                    Button { withAnimation { expanded.toggle() } } label: {
                        HStack {
                            Text(expanded ? "收起授权设置" : "展开授权设置")
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("portalPermissions")
                        .accessibilityValue(expanded ? "已展开" : "已收起")
                    if expanded {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(capabilities, id: \.0) { capability in
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(capability.1, systemImage: capability.2).font(.headline)
                                    Toggle("允许读取", isOn: grant(capability.0 + ".read")).disabled(portal.authorizing != nil || portal.healthRequesting)
                                    if capability.0 != "location" { Toggle("允许写入", isOn: grant(capability.0 + ".write")).disabled(portal.authorizing != nil || portal.healthRequesting) }
                                    Text("系统权限：\(portal.permissions.permission(capability.0).label)").font(.caption).foregroundStyle(ClientTheme.secondary)
                                    if portal.authorizing == capability.0 { ProgressView("等待系统授权结果…") }
                                    if !portal.permissions.permission(capability.0).available {
                                        if portal.permissions.permission(capability.0).canRequest {
                                            Button("请求系统权限并允许读取") { portal.setGrant(capability.0 + ".read", enabled: true) }
                                        } else {
                                            Button("前往系统设置授权") { openSettings() }
                                            Text("在系统中允许后，返回此页开启 Being 访问。").font(.caption).foregroundStyle(ClientTheme.secondary)
                                        }
                                    }

                                }
                                if capability.0 != "location" { Divider() }
                            }
                            Button("打开系统应用权限设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                            SettingsNote(text: "iOS 日历和提醒事项读取需要系统完整访问权限，Being 的写入仍由独立开关控制。通讯录支持仅所选联系人，定位支持大致位置。")
                        }.padding(.top, 12).padding(.trailing, 8)
                    }
                }.disabled(store.connection == nil)
            }
            SettingsSection(title: "Apple 健康", icon: "heart.fill") {
                HStack {
                    Text(portal.healthLinked ? "已关联当前 Being" : "尚未关联").font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("portalHealthStatus")
                    Spacer()
                    if portal.healthRequesting { ProgressView() }
                }
                SettingsNote(text: "关联活动、睡眠、锻炼、心肺、营养和身体指标等 \(IOSPortalHealth.categories.count) 类健康数据，由你在系统页选择共享范围。只读取，不修改健康记录。")
                if portal.healthLinked {
                    SettingsNote(text: "新增类型需点击管理健康关联与共享范围，再点击继续，向系统请求共享。")
                    SettingsNote(text: "关联状态仅表示已连接此数据来源。实际读取范围由 Apple 健康控制，iOS 不向 App 透露每类数据是否允许读取。")
                    Button("管理健康关联与共享范围") { portal.notice = nil; linkingHealth = true }
                        .disabled(portal.healthRequesting || portal.authorizing != nil)
                    Button("断开 Apple 健康关联", role: .destructive) { portal.revokeHealthGrants() }
                        .accessibilityIdentifier("portalHealthDisconnect")
                    SettingsNote(text: "调整共享内容：健康 App → 个人头像 → App → Being。断开关联立即停止当前 Being 的后续查询，不会删除它已收到的数据。")
                } else {
                    Button(portal.healthRequesting ? "正在关联 Apple 健康…" : "关联 Apple 健康") {
                        portal.notice = nil; linkingHealth = true
                    }.buttonStyle(SettingsActionStyle())
                        .disabled(portal.healthRequesting || portal.authorizing != nil || !portal.health.available)
                        .accessibilityIdentifier("portalHealthConnect")
                    SettingsNote(text: "将打开系统健康关联页，由你选择共享内容。若此前已选择过，iOS 可能不再弹出该页面，可到健康 App 中调整。")
                }
                if !portal.health.available { SettingsNote(text: "此设备暂不支持 Apple 健康。") }
            }.disabled(store.connection == nil)
            SettingsSection(title: "文件工作区", icon: "folder") {
                Toggle("允许文件读写与搜索", isOn: Binding(get: { portal.options.files }, set: { value in portal.configure { $0.files = value } })).disabled(store.connection == nil)
                SettingsNote(text: "每个 Being 使用独立目录。导入的文件可被该 Being 读取和修改，单文件不超过 10 MB。卸载应用会删除工作区，请及时导出。")
                HStack {
                    Button("导入文件") { importOwner = store.connection; importing = true }.disabled(store.connection == nil)
                    Spacer()
                    Button("刷新") { refreshFiles() }.disabled(store.connection == nil)
                }.frame(minHeight: 44)
                if directory != "." { Button("返回上级目录") { let parent = (directory as NSString).deletingLastPathComponent; directory = parent.isEmpty ? "." : parent; refreshFiles() } }
                if files.isEmpty { SettingsNote(text: "当前目录为空") }
                ForEach(files) { file in
                    Button {
                        if file.directory { directory = file.path; refreshFiles() }
                        else {
                            do {
                                guard let workspace = portal.workspace else { return }
                                export = PortalExport(data: try workspace.read(file.path), name: file.name); exporting = true
                            } catch { portal.notice = "无法导出文件，请确认文件存在且不超过 10 MB。" }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: file.directory ? "folder" : "doc")
                            Text(file.name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: file.directory ? "chevron.right" : "square.and.arrow.up")
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
            SettingsSection(title: "最近活动", icon: "clock.arrow.circlepath") {
                if portal.activity.isEmpty { SettingsNote(text: "暂无执行记录") }
                ForEach(portal.activity.prefix(20)) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.tool).font(.caption.monospaced()).lineLimit(2)
                        HStack { Text(event.status); Spacer(); Text(event.time, format: .dateTime.month().day().hour().minute()) }.font(.caption).foregroundStyle(ClientTheme.secondary)
                    }
                }
            }
            SettingsNote(text: "当前支持文件、日历、提醒事项、通讯录、前台定位和 Apple 健康关联。Shell、网页抓取、其他应用通知、地点提醒和屏幕控制暂不支持。")
        }.navigationTitle("本机 Portal")
        .task { portal.bind(store.connection); name = portal.options.name; refreshFiles() }
        .onChange(of: store.connection) { value in portal.bind(value); name = portal.options.name; directory = "."; linkingHealth = false; export = nil; refreshFiles() }
        .onChange(of: phase) { if $0 == .active { portal.refreshPermissions() } }
        .sheet(isPresented: $linkingHealth) {
            IOSPortalHealthConnectionView(portal: portal)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(portal.healthRequesting)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            guard importOwner == store.connection, let workspace = portal.workspace else { portal.notice = "Being 已切换，请重新导入。"; return }
            do {
                let urls = try result.get()
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    let data = try handle.read(upToCount: LocalPortalRules.maxFileSize + 1) ?? Data()
                    try workspace.write(url.lastPathComponent, data: data, overwrite: false)
                }
                directory = "."; refreshFiles()
            } catch { portal.notice = error is PortalError ? error.localizedDescription : "文件导入失败，请重试。" }
        }
        .fileExporter(isPresented: $exporting, document: export, contentType: .data, defaultFilename: export?.name ?? "file") { result in
            if case .failure = result { portal.notice = "文件导出失败，请重试。" }; export = nil
        }
    }
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
    private func grant(_ key: String) -> Binding<Bool> { Binding(get: { portal.effectiveGrant(key) }, set: { portal.setGrant(key, enabled: $0) }) }
    private func refreshFiles() {
        do { files = try portal.workspace?.list(directory).compactMap(PortalFileRow.init) ?? [] }
        catch { files = []; portal.notice = "工作区读取失败，请重试。" }
    }
}
private struct PortalFileRow: Identifiable {
    let path: String; let name: String; let directory: Bool
    var id: String { path }
    init?(_ object: [String: Any]) {
        guard let path = object["path"] as? String, let name = object["name"] as? String else { return nil }
        self.path = path; self.name = name; directory = object["is_dir"] as? Bool == true
    }
}
private struct PortalExport: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    var name: String
    init(data: Data, name: String) { self.data = data; self.name = name }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data(); name = configuration.file.preferredFilename ?? "file" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
