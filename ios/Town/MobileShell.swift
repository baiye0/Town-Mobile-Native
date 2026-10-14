import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case chat, firesides, mail, bonfire, seeds, embers, scrolls, announcements, contacts, home
    var id: String { rawValue }
    var title: String { ["chat":"对话","firesides":"围炉","mail":"私信","bonfire":"篝火","seeds":"种子花园","embers":"书架","scrolls":"卷轴","announcements":"公告","contacts":"通讯录","home":"小镇广场"][rawValue]! }
    var icon: String { ["chat":"bubble.left.and.bubble.right","firesides":"person.2","mail":"envelope","bonfire":"flame","seeds":"leaf","embers":"books.vertical","scrolls":"doc.text","announcements":"megaphone","contacts":"person.crop.rectangle.stack","home":"house"][rawValue]! }
}
@MainActor @Observable final class NavigationState {
    var selected = "chat"
    var sidebar = false
    var keyboardVisible = false
    var sceneSheet: String?
    var tabs: [Destination] {
        didSet { UserDefaults.standard.set(tabs.map(\.rawValue), forKey: "navigation.tabs") }
    }
    init() {
        let saved = (UserDefaults.standard.stringArray(forKey: "navigation.tabs") ?? []).compactMap(Destination.init(rawValue:))
        tabs = saved.contains(.chat) && Set(saved).count == saved.count && saved.count <= 4 ? saved : [.chat, .firesides, .mail, .bonfire]
    }
}
struct MobileShell: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nav = NavigationState()
    @AppStorage("glassEffects") private var glass = true
    @State private var social = SocialStore()
    @State private var drag: CGFloat = 0
    @State private var search = ""
    @State private var renameID: String?
    @State private var deletingID: String?
    @State private var renameText = ""
    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.84, 340)
            let progress = min(width, max(0, (nav.sidebar ? width : 0) + drag))
            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                TabView(selection: $nav.selected) {
                    ForEach(nav.tabs) { item in
                        Tab(value: item.rawValue) { destination(item).toolbar(glass ? .automatic : .hidden, for: .tabBar) } label: { Image(systemName: item.icon).accessibilityLabel(item.title) }.badge(social.unread(item))
                    }
                    Tab(value: "more") { MoreView().toolbar(glass ? .automatic : .hidden, for: .tabBar) } label: { Image(systemName: "square.grid.2x2").accessibilityLabel("更多") }
                }
                .toolbar(glass ? .automatic : .hidden, for: .tabBar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !glass && !nav.keyboardVisible {
                        HStack(spacing: 0) {
                            ForEach(nav.tabs.map(\.rawValue) + ["more"], id: \.self) { id in
                                let item = Destination(rawValue: id)
                                Button { nav.selected = id } label: {
                                    Image(systemName: item?.icon ?? "square.grid.2x2")
                                        .font(.system(size: 22)).frame(maxWidth: .infinity).frame(height: 48)
                                        .background(nav.selected == id ? ClientTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(alignment: .topTrailing) {
                                            if let item, social.unread(item) > 0 { Circle().fill(.red).frame(width: 7, height: 7).padding(7) }
                                        }
                                }.buttonStyle(.plain).accessibilityLabel(item?.title ?? "更多")
                                    .accessibilityAddTraits(nav.selected == id ? .isSelected : [])
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 8).background(ClientTheme.background)
                    }
                }
                .offset(x: progress)
                .overlay {
                    if progress > 0 {
                        Color.black.opacity(0.32 * progress / width).ignoresSafeArea().offset(x: progress)
                            .onTapGesture { close() }
                            .gesture(DragGesture().onChanged { drag = min(0, $0.translation.width) }.onEnded { finish($0, width) })
                    }
                }
                .accessibilityHidden(nav.sidebar)
                if progress > 0 {
                    sidebar.frame(width: width).frame(maxHeight: .infinity).background(ClientTheme.background)
                        .offset(x: progress - width)
                        .shadow(color: .black.opacity(0.08), radius: 20, x: 8)

                }
                if !nav.sidebar && nav.selected == "chat" {
                    Color.clear.frame(width: 22).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 12).onChanged { if !store.busy && $0.translation.width > abs($0.translation.height) { drag = max(0, $0.translation.width) } }.onEnded { finish($0, width) })
                        .accessibilityHidden(true)
                }
            }.animation(reduceMotion ? nil : .interactiveSpring(response: 0.32, dampingFraction: 0.88), value: nav.sidebar)
        }
        .environment(nav).environment(social)
        .sheet(isPresented: Binding(get: { nav.sceneSheet != nil }, set: { if !$0 { nav.sceneSheet = nil } })) {
            if nav.sceneSheet == "details" { SceneDetails() } else { SceneEditor(binding:nav.sceneSheet == "bind") }
        }
        .task { social.startLive() }
        .onChange(of: phase) { _, phase in if phase == .active { social.startLive() } else { social.stopLive() } }
        .alert("删除场景？", isPresented: Binding(get: { deletingID != nil },set: { if !$0 { deletingID = nil } })) {
            Button("取消",role:.cancel) { deletingID = nil }
            Button("确认删除",role:.destructive) { if let id = deletingID { store.delete(id) }; deletingID = nil }
        } message: { Text("确定从本机场景列表中删除「\(store.rooms.first { $0.id == deletingID }?.title ?? "")」？历史记录会保留，仍可开启「显示全部场景上下文」查看。") }
        .alert("重命名场景", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renameID = nil }
            Button("保存") { if let id = renameID { store.rename(id, renameText) }; renameID = nil }
        }
    }
    @ViewBuilder private func destination(_ item: Destination) -> some View {
        switch item {
        case .chat: RootView()
        case .firesides, .mail, .bonfire: SocialView(kind: item)
        default: HistoryStack { CatalogView(category: item.rawValue) }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("ClientLogo").resizable().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Being").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("收起侧栏", systemImage: "sidebar.left") { close() }
                    .labelStyle(.iconOnly).font(.system(size: 18)).frame(width: 44, height: 44)
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(ClientTheme.secondary)
                TextField("搜索场景", text: $search).font(.system(size: 15)).submitLabel(.search)
            }.padding(.horizontal, 12).frame(height: 44)
                .background(ClientTheme.surface, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16)
            Button { nav.sceneSheet = "create"; nav.selected = "chat"; close() } label: {
                Label("新建场景", systemImage: "square.and.pencil")
                    .font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).frame(height: 46)
            }.buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
                .disabled(store.busy || store.connection == nil)
            List {
                ForEach(store.rooms.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { room in
                    Button { store.selectScene(room.id); nav.selected = "chat"; close() } label: {
                        HStack(spacing: 11) {
                            Image(systemName: room.id == store.mainID ? "bubble.left.and.bubble.right" : "bubble.left")
                                .font(.system(size: 17)).frame(width: 22).foregroundStyle(ClientTheme.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(room.title).font(.system(size: 15, weight: room.id == store.selected ? .semibold : .regular))
                                    .foregroundStyle(ClientTheme.text).lineLimit(1)
                                Text(room.updated, style: .date).font(.system(size: 11)).foregroundStyle(ClientTheme.secondary)
                            }
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
                            .background(room.id == store.selected ? ClientTheme.text.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        .swipeActions(edge: .trailing) { Button("删除场景", role: .destructive) { deletingID = room.id } }
                        .swipeActions(edge: .leading) { Button("重命名") { renameText = room.title; renameID = room.id }.tint(.accentColor) }
                        .disabled(store.busy)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).environment(\.defaultMinListRowHeight, 0)
                .refreshable { await store.history() }.scrollDismissesKeyboard(.interactively)
            VStack(spacing: 0) {
                Divider().overlay(ClientTheme.text.opacity(0.04)).padding(.bottom, 6)
                Button { nav.sceneSheet = "bind"; close() } label: {
                    Label("绑定已有场景", systemImage: "link").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 42)
                }.disabled(store.connection == nil || store.busy)
                Button { nav.sceneSheet = "details"; close() } label: {
                    Label("场景详情", systemImage: "info.circle").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 42)
                }.disabled(store.current == nil)
                Toggle("显示全部场景上下文",isOn:Binding(get:{store.showAllScenes},set:{store.showAllScenes=$0}))
                    .frame(minHeight: 44).disabled(store.current == nil)
                Toggle("显示 SBS 消息",isOn:Binding(get:{store.showAllScenes || store.showSBS},set:{store.showSBS=$0;store.saveSBS()}))
                    .frame(minHeight: 44).disabled(store.showAllScenes || store.current == nil)
            }.font(.system(size: 14)).buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 12)
            Divider().padding(.horizontal, 16)
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle").font(.system(size: 25)).foregroundStyle(ClientTheme.secondary)
                Text(store.connection?.being ?? "未连接").font(.system(size: 14, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Button("设置", systemImage: "gearshape") { nav.selected = "more"; close() }
                    .labelStyle(.iconOnly).font(.system(size: 18)).frame(width: 44, height: 44)
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)
        }.foregroundStyle(ClientTheme.text)
    }
    private func close() { withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88)) { nav.sidebar = false; drag = 0 } }
    private func finish(_ value: DragGesture.Value, _ width: CGFloat) {
        guard !store.busy else { drag = 0; return }
        let projected = (nav.sidebar ? width : 0) + value.predictedEndTranslation.width
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88)) { nav.sidebar = projected > width * 0.4; drag = 0 }
    }
}
struct NavigationSettings: View {
    @Environment(NavigationState.self) private var nav
    var body: some View {
        List {
            Section("底部导航") {
                ForEach(nav.tabs) { item in
                    HStack { Label(item.title, systemImage: item.icon); Spacer(); if item != .chat { Button("移除") { nav.tabs.removeAll { $0 == item }; nav.selected = "more" }.font(.caption) } }
                }.onMove { nav.tabs.move(fromOffsets: $0, toOffset: $1) }
            }
            Section("可添加") {
                ForEach(Destination.allCases.filter { !nav.tabs.contains($0) }) { item in
                    Button { if nav.tabs.count < 4 { nav.tabs.append(item) } } label: { Label(item.title, systemImage: "plus.circle") }.disabled(nav.tabs.count >= 4)
                }
            }
            Section { Button("恢复默认") { nav.tabs = [.chat, .firesides, .mail, .bonfire] } }
        }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle("自定义导航").environment(\.editMode, .constant(.active))
    }
}
struct MoreView: View {
    @Environment(Store.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("glassEffects") private var glass = true
    var body: some View {
        HistoryStack {
            List {
                Section { HStack(spacing: 16) { Image("ClientLogo").resizable().frame(width: 48,height: 48).clipShape(RoundedRectangle(cornerRadius: 12)); VStack(alignment: .leading, spacing: 6) { Text("Being").font(.title2.bold()); Text(store.connection?.being ?? "Being").foregroundStyle(ClientTheme.secondary) } }.padding(.vertical, 12) }
                Section("小镇") {
                    ForEach([Destination.firesides, .bonfire, .mail]) { item in HistoryLink { SocialView(kind: item) } label: { Label(item.title, systemImage: item.icon) } }
                    ForEach(["home","seeds","embers","scrolls","announcements","contacts"], id: \.self) { category in
                        HistoryLink { CatalogView(category: category) } label: { Label(["home":"小镇广场","seeds":"种子花园","embers":"书架","scrolls":"卷轴","announcements":"公告","contacts":"通讯录"][category]!, systemImage: ["home":"house","seeds":"leaf","embers":"books.vertical","scrolls":"doc.text","announcements":"megaphone","contacts":"person.crop.rectangle.stack"][category]!) }
                    }
                }
                Section("设置") {
                    HistoryLink { SettingsView() } label: { Label("连接 Being", systemImage: "link") }
                    HistoryLink { PairingView() } label: { Label("连接 Being Town", systemImage: "person.badge.key") }
                    HistoryLink { ModelSettingsView() } label: { Label("模型设置", systemImage: "cpu") }
                    HistoryLink { NavigationSettings() } label: { Label("自定义底部导航", systemImage: "slider.horizontal.3") }
                    Toggle("玻璃效果", isOn: $glass)
                    Picker("外观", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                }
            }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle("更多")
        }
    }
}
