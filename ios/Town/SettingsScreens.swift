import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var social: SocialStore
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.dynamicTypeSize) private var typeSize
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    var body: some View {
        HistoryStack {
            SettingsPage {
                SettingsCard {
                    HistoryLink { BeingConnectionView() } label: {
                        HStack(spacing: 14) {
                            Image("ClientLogo").resizable().scaledToFit().frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 15)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.connection?.being ?? "连接你的 Being").font(.title3.weight(.semibold))
                                Text(store.connection == nil ? "尚未连接 · 点击开始对话" : "已连接 · \(URL(string: store.connection?.endpoint ?? "")?.host ?? "Being")")
                                    .font(.caption).foregroundStyle(ClientTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(ClientTheme.secondary)
                        }.padding(18).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("beingConnection")
                }
                SettingsSectionLabel(title: "设置")
                SettingsCard {
                    HistoryLink { ConversationSettingsView() } label: { SettingsRow(title: "对话设置", icon: "bubble.left.and.bubble.right", subtitle: "SBS · 阅读字号") }
                    SettingsDivider()
                    HistoryLink { ModelSettingsView() } label: { SettingsRow(title: "模型设置", icon: "cpu", subtitle: "线路、模型与思考深度") }
                    SettingsDivider()
                    HistoryLink { NotificationSettingsView() } label: { SettingsRow(title: "通知设置", icon: "bell") }
                    SettingsDivider()
                    HistoryLink { AppearanceSettingsView() } label: { SettingsRow(title: "外观", icon: "paintpalette", subtitle: appearanceTitle(appearance)) }
                    SettingsDivider()
                    HistoryLink { NavigationSettings() } label: { SettingsRow(title: "底部导航", icon: "slider.horizontal.3", subtitle: "调整入口与顺序") }
                }.buttonStyle(.plain)
                SettingsSectionLabel(title: "Being Town")
                SettingsCard {
                    HistoryLink { PairingView() } label: {
                        SettingsRow(title: "小镇连接", icon: "link", subtitle: social.identity.map { $0.name.isEmpty ? $0.id : $0.name } ?? "尚未配对")
                    }.buttonStyle(.plain)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 10) {
                    ForEach(Destination.allCases.filter { $0 != .chat }) { item in
                        HistoryLink { townDestination(item) } label: {
                            VStack(spacing: 12) {
                                Image(systemName: item.icon).font(.system(size: 23)).frame(height: 28).accessibilityHidden(true)
                                Text(item.title).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(.horizontal, 6).padding(.vertical, 20)
                                .background(ClientTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                                .contentShape(RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                }
                SettingsSectionLabel(title: "应用")
                SettingsCard {
                    HistoryLink { AppUpdateSettingsView() } label: { SettingsRow(title: "应用更新", icon: "arrow.down.circle", subtitle: "版本 \(version)") }.buttonStyle(.plain)
                }
                Text("Being · \(version)").font(.caption).foregroundStyle(ClientTheme.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.navigationTitle("更多")
        }
    }
    @ViewBuilder private func townDestination(_ item: Destination) -> some View {
        switch item {
        case .firesides, .mail, .bonfire: SocialView(kind: item)
        default: CatalogView(category: item.rawValue)
        }
    }
}

private func appearanceTitle(_ value: String) -> String {
    switch value { case "light": "浅色"; case "dark": "深色"; default: "跟随系统" }
}

struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("glassEffects") private var glass = true
    var body: some View {
        SettingsPage {
            SettingsSectionLabel(title: "主题")
            SettingsCard {
                ForEach(["system", "light", "dark"], id: \.self) { value in
                    if value != "system" { SettingsDivider() }
                    Button { appearance = value } label: {
                        HStack(spacing: 14) {
                            SettingsIcon(name: value == "system" ? "circle.lefthalf.filled" : value == "light" ? "sun.max" : "moon")
                            Text(appearanceTitle(value)).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: appearance == value ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(appearance == value ? ClientTheme.text : ClientTheme.secondary)
                        }.padding(16).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(appearanceTitle(value))
                        .accessibilityAddTraits(appearance == value ? .isSelected : [])
                }
            }
            if #available(iOS 26.0, *) {
                SettingsSection(title: "界面效果", icon: "square.on.square") {
                    Toggle("玻璃效果", isOn: $glass)
                    SettingsNote(text: "为导航栏和对话输入框使用通透的玻璃效果。")
                }
            }
        }.navigationTitle("外观")
    }
}

struct ConversationSettingsView: View {
    @EnvironmentObject private var store: Store
    @AppStorage("reading.size") private var readingSize = 16.0
    var body: some View {
        SettingsPage {
            SettingsSection(title: "SBS", icon: "sparkles") {
                if store.connection != nil { SBSControlView() }
                else { SettingsNote(text: "连接 Being 后可配置 SBS") }
            }
            SettingsSection(title: "阅读", icon: "textformat.size") {
                Stepper("阅读字号 · \(Int(readingSize))", value: $readingSize, in: 12...24)
                Text("从一个想法开始，让对话自然发生。")
                    .font(.system(size: readingSize)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).background(ClientTheme.background, in: RoundedRectangle(cornerRadius: 14))
                SettingsNote(text: "调整对话正文的文字大小。")
            }
        }.navigationTitle("对话设置")
    }
}

struct NotificationSettingsView: View {
    @AppStorage("notify.completed") private var notifications = false
    @AppStorage("notify.social.enabled") private var socialNotifications = false
    @AppStorage("notify.social.mail") private var notifyMail = false
    @AppStorage("notify.social.firesides") private var notifyFiresides = false
    @AppStorage("notify.social.bonfire") private var notifyBonfire = false
    var body: some View {
        SettingsPage {
            SettingsSection(title: "对话通知", icon: "bubble.left.and.bubble.right") {
                Toggle("对话完成通知", isOn: Binding(get: { notifications }, set: { value in
                    if value { Task { notifications = await CompletionNotifications.shared.enable() } }
                    else { notifications = false }
                }))
                SettingsNote(text: "应用仍在运行时提示完成。系统暂停或关闭应用后，返回应用会核对回复。")
            }
            SettingsSection(title: "小镇通知", icon: "bell") {
                Toggle("小镇通知总开关", isOn: Binding(get: { socialNotifications }, set: { value in
                    if value { Task { socialNotifications = await CompletionNotifications.shared.enable() } }
                    else { socialNotifications = false }
                }))
                Divider()
                Toggle("私信", isOn: $notifyMail).disabled(!socialNotifications)
                Toggle("围炉", isOn: $notifyFiresides).disabled(!socialNotifications)
                Toggle("篝火", isOn: $notifyBonfire).disabled(!socialNotifications)
                SettingsNote(text: "配对 Town 后接收新消息提醒，不展示消息正文。")
            }
        }.navigationTitle("通知设置")
    }
}

struct AppUpdateSettingsView: View {
    @StateObject private var update = AppUpdateStore()
    var body: some View {
        SettingsPage {
            SettingsSection(title: "应用更新", icon: "arrow.down.circle") {
                LabeledContent("当前版本", value: update.currentVersion)
                SettingsNote(text: update.message)
                if update.phase == .checking { ProgressView().frame(maxWidth: .infinity) }
                Button("检查更新") { Task { await update.check() } }
                    .buttonStyle(SettingsActionStyle()).disabled(update.phase == .checking)
                if update.phase == .available, let url = update.releaseURL {
                    Link("打开发布页", destination: url).buttonStyle(SettingsActionStyle(prominent: false))
                }
            }
            SettingsNote(text: "iOS 版本通过 TestFlight 或 App Store 安装。发布页提供版本信息。")
        }.navigationTitle("应用更新").task { if update.phase == .idle { await update.check() } }
    }
}
