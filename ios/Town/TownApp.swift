import SwiftUI

@main struct TownApp: App {
    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--verify-keychain") { KeychainCheck.run() }
        #endif
    }
    @State private var store = Store()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene { WindowGroup { MobileShell().environment(store).buttonStyle(BeingDefaultButtonStyle()).toggleStyle(BeingToggleStyle()).background(ClientTheme.background).tint(ClientTheme.accent).preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil) } }
}
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(NavigationState.self) private var nav
    @State private var settings = false
    @State private var speech = SpeechInput()
    @State private var draftBeforeSpeech = ""
    @FocusState private var inputFocused: Bool
    @AppStorage("glassEffects") private var glass = true
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            VStack(spacing: 0) {
                ChatView(dismissKeyboard: { inputFocused = false })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                composer
            }
                .background { ClientTheme.background.ignoresSafeArea() }
                .navigationTitle(store.current?.title ?? "Being")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { AdaptiveToolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("对话记录", systemImage: "line.3.horizontal") { withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { nav.sidebar = true } }.disabled(store.busy) }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("刷新",systemImage:"arrow.clockwise") { Task { await store.history() } }.disabled(store.historyLoading || store.busy || store.connection == nil)
                        Button("新建场景", systemImage: "square.and.pencil") { nav.sceneSheet = "create" }.disabled(store.busy || store.connection == nil)
                        Button("设置", systemImage: "person.crop.circle") { nav.selected = "more" }.disabled(store.busy)
                    }
                 } }

                .sheet(isPresented: $settings) { SettingsView() }
                .toolbar(inputFocused || !glass ? .hidden : .visible, for: .tabBar)
        }
        .task(id: store.connection?.endpoint) { await store.history() }
        .onChange(of: phase) { _, value in if value == .active && !store.busy { Task { await store.history() } } else if value == .background { speech.stop() } }
        .onChange(of: inputFocused) { _, value in nav.keyboardVisible = value }
        .onChange(of: nav.sidebar) { _, opened in if opened { inputFocused = false } }
        .onChange(of: nav.selected) { _, _ in inputFocused = false }
        .onChange(of: store.selected) { _, _ in inputFocused = false; speech.stop() }
        .onChange(of: store.connection?.endpoint) { _, _ in speech.stop() }
        .onDisappear { inputFocused = false; nav.keyboardVisible = false; speech.stop() }
    }
    private var composer: some View {
        @Bindable var store = store
        return VStack(spacing: 8) {
            if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.red).padding(.horizontal).accessibilityAddTraits(.updatesFrequently) }
            GlassEffectContainer(spacing: 12) {
                Group {
                if speech.active {
                    VoiceInputBar(speech: speech, cancel: {
                        speech.stop(); store.draft = draftBeforeSpeech
                    })
                } else {
                HStack(alignment: .center, spacing: 8) {
                    TextField("说点什么…", text: $store.draft, axis: .vertical)
                        .focused($inputFocused).lineLimit(1...6).disabled(speech.active).font(.system(size: 16)).padding(.vertical, 10).padding(.leading, 18).accessibilityLabel("消息")
                    Button {
                        inputFocused = false
                        if speech.active { speech.finish() }
                        else {
                            let original = store.draft
                            draftBeforeSpeech = original
                            Task { await speech.start(update: { text in store.draft = original + (original.isEmpty ? "" : " ") + text },failure: { store.notice = $0 }) }
                        }
                    } label: {
                        Image(systemName:speech.active ? "stop.circle.fill" : "mic").font(.system(size:20)).frame(width:40,height:44)
                            .foregroundStyle(speech.active ? Color.red : ClientTheme.secondary)
                    }.accessibilityLabel(speech.active ? "停止语音输入" : "语音输入").disabled(store.busy)
                    if store.busy || store.connection == nil || !store.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    Button {
                        inputFocused = false
                        if store.connection == nil { settings = true }
                        else if store.busy { Task { await store.stop() } }
                        else { store.send() }
                    } label: {
                        Image(systemName: store.busy ? "stop.fill" : store.connection == nil ? "link" : "arrow.up")
                            .font(.system(size: 18, weight: .semibold)).frame(width: 36, height: 36)
                            .foregroundStyle(ClientTheme.buttonText).background(ClientTheme.accent, in: Circle())
                    }.accessibilityLabel(store.busy ? "停止生成" : store.connection == nil ? "连接 Being" : "发送")
                        .disabled(speech.active || (store.connection != nil && !store.busy && store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .frame(width: 44, height: 44)
                    }
                }.padding(.trailing, 6)
                }
                }.frame(minHeight: 48).beingSurface(radius: 24).padding(.horizontal, 16)
            }
        }.padding(.top, 12).padding(.bottom, inputFocused ? 8 : 10)
    }
}
struct VoiceInputBar: View {
    let speech: SpeechInput
    let cancel: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: cancel) {
                Image(systemName: "trash").font(.system(size: 20)).frame(width: 44, height: 44)
            }.accessibilityLabel("取消语音输入").foregroundStyle(ClientTheme.text)
            if let start = speech.startedAt {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(start)))
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 15, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(ClientTheme.secondary)
                }.frame(minWidth: 40)
            }
            if speech.startedAt == nil || speech.finishing {
                ProgressView().frame(maxWidth: .infinity)
                    .accessibilityLabel(speech.finishing ? "正在识别" : "正在连接麦克风")
            } else {
                GeometryReader { geometry in
                    let count = max(1, min(speech.levels.count, Int(geometry.size.width / 7)))
                    HStack(spacing: 3) {
                        ForEach(0..<count, id: \.self) { index in
                            Capsule().fill(ClientTheme.text)
                                .frame(width: 3, height: 3 + CGFloat(speech.levels[speech.levels.count - count + index]) * 25)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(height: 32).accessibilityLabel("正在语音输入")
            }
            Button { speech.finish() } label: {
                Image(systemName: "checkmark").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white).frame(width: 36, height: 36)
                    .background(ClientTheme.chatSent, in: Circle()).frame(width: 44, height: 44)
            }.accessibilityLabel("完成语音输入").disabled(speech.startedAt == nil || speech.finishing)
        }.padding(.horizontal, 6).padding(.vertical, 2).frame(minHeight: 48)
    }
}
struct ChatView: View {
    var dismissKeyboard: () -> Void = {}
    @State private var showConnection = false
    @State private var nearBottom = true
    @State private var followLatest = true
    @State private var userScrolling = false
    @State private var visibleCount = 80
    @State private var bottomRequest = 0
    @Environment(Store.self) private var store
    var body: some View {
        let allMessages = store.displayMessages
        let messages = Array(allMessages.suffix(visibleCount))
        ScrollViewReader { proxy in
            ScrollView {
                if !messages.isEmpty {
                    VStack(spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            if let time = message.timestamp, index == 0 || messages[index - 1].timestamp?.prefix(16) != time.prefix(16) {
                                Text(chatTime(time)).font(.caption2).foregroundStyle(ClientTheme.secondary).frame(maxWidth:.infinity).padding(.vertical,4)
                            }
                            if message.kind == "marker" { HStack { Rectangle().frame(height:1); Text(message.text).font(.caption); Rectangle().frame(height:1) }.foregroundStyle(ClientTheme.secondary).padding(.vertical,8) }
                            else { HStack(alignment: .top) {
                                if message.role == "user" { Spacer(minLength: 40) }
                                VStack(alignment: .leading, spacing: 9) {
                                    if store.showAllScenes, message.sceneID != store.selected { Text(message.sceneID ?? "未标记场景").font(.caption).foregroundStyle(ClientTheme.secondary).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading) }
                                    MarkdownText(text: message.text, foreground:message.role == "user" ? .white : ClientTheme.text, fillsWidth:false).tint(message.role == "user" ? .white : ClientTheme.accent)
                                }.padding(16)
                                    .background(message.role == "user" ? ClientTheme.chatSent : ClientTheme.chatReply, in: RoundedRectangle(cornerRadius: 22))
                                    .contextMenu { ShareLink(item: message.text); Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text } }
                                if message.role != "user" { Spacer(minLength: 24) }
                            }.id(message.id) }
                        }
                        if store.busy && !store.activity.isEmpty && store.activity != "正在回复" {
                            ThinkingIndicator(activity: store.activity)
                        }
                        if store.historyLoading { ProgressView() }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                    }.padding(24)
                } else {
                    VStack(alignment: .leading, spacing: 30) {
                        ZStack {
                            Circle().fill(ClientTheme.surface).frame(width: 106, height: 106)
                            Image("ClientLogo").resizable().scaledToFit().frame(width: 106,height: 106).clipShape(RoundedRectangle(cornerRadius: 24))
                        }.padding(.top, 48)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.connection == nil ? "从一个想法开始" : "Being").font(.system(size: 35, weight: .regular))
                            Text(store.connection == nil ? "连接你的 Being，继续对话。" : "当前场景还没有对话。").font(.subheadline).foregroundStyle(ClientTheme.secondary)
                            if store.connection == nil { Button("连接我的 Being") { showConnection = true }.beingButton(prominent: true).foregroundStyle(ClientTheme.buttonText).padding(.top, 16) }
                        }
                    }.frame(maxWidth: 520, alignment: .leading).padding(.horizontal, 28).padding(.bottom, 20).frame(maxWidth: .infinity)
                }
            }.scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onScrollPhaseChange { _, phase in
                    userScrolling = phase == .interacting || phase == .decelerating
                    if phase == .interacting { followLatest = false }
                    if phase == .idle && nearBottom { followLatest = true }
                }
                .onScrollGeometryChange(for: ChatScrollMetrics.self) { geometry in
                    ChatScrollMetrics(bottom: geometry.contentSize.height - geometry.visibleRect.maxY < 80,
                                      top: geometry.contentOffset.y + geometry.contentInsets.top < 160)
                } action: { _, metrics in
                    nearBottom = metrics.bottom
                    if metrics.bottom { followLatest = true } else if userScrolling { followLatest = false }
                    if metrics.top && userScrolling && visibleCount < allMessages.count {
                        let anchor = messages.first?.id
                        visibleCount += 80
                        Task { @MainActor in await Task.yield(); if let anchor { proxy.scrollTo(anchor, anchor: .top) } }
                    }
                }
                .task(id: bottomRequest) {
                    guard bottomRequest > 0 else { return }
                    await Task.yield()
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: messages.last?.text) { _, _ in if followLatest { bottomRequest += 1 } }
                .onChange(of: allMessages.count) { _, _ in if followLatest { bottomRequest += 1 } }
                .onChange(of: store.selected) { _, _ in followLatest = true; visibleCount = 80; bottomRequest += 1 }
                .onChange(of: store.showAllScenes) { _, _ in followLatest = true; visibleCount = 80; bottomRequest += 1 }
                .overlay(alignment: .bottomTrailing) {
                    if !nearBottom && !messages.isEmpty {
                        Button { followLatest = true; visibleCount = 80; bottomRequest += 1 } label: {
                            Image(systemName: "arrow.down").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        }.beingButton().buttonBorderShape(.circle).accessibilityLabel("回到底部").padding(16)
                    }
                }
        }.background(ClientTheme.background).sheet(isPresented: $showConnection) { SettingsView() }
    }
}
private struct ChatScrollMetrics: Equatable { var bottom: Bool; var top: Bool }
func chatTime(_ value:String) -> String {
    let fractional=ISO8601DateFormatter(); fractional.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
    guard let date=fractional.date(from:value) ?? ISO8601DateFormatter().date(from:value) else{return String(value.replacingOccurrences(of:"T",with:" ").prefix(16))}
    let format=DateFormatter();format.dateStyle = Calendar.current.isDateInToday(date) ? .none : .medium;format.timeStyle = .short
    return format.string(from:date)
}
struct HistoryView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                Button("开启新对话", systemImage: "plus") { store.newChat(); dismiss() }.disabled(store.connection == nil)
                ForEach(store.rooms.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { room in
                    Button { store.selected = room.id; dismiss() } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(room.title).foregroundStyle(ClientTheme.text); Text(room.updated, style: .date).font(.caption).foregroundStyle(ClientTheme.secondary) }.padding(.vertical, 6)
                    }.swipeActions { Button("删除本地记录", role: .destructive) { store.delete(room.id) } }
                }
            }.overlay { if store.rooms.isEmpty { ContentUnavailableView("暂无对话记录。", systemImage: "bubble.left.and.bubble.right") } }
                .searchable(text: $query, prompt: "搜索对话")
                .refreshable { await store.history() }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle("对话")
                .toolbar { AdaptiveToolbar {  ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }  } }
        }.task { await store.history() }
    }
}
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var connecting = false
    @State private var model = ""
    @State private var provider = ""
    var body: some View {
        HistoryStack {
            Form {
                Section {
                    Label("Being", systemImage: "sparkle").font(.headline)

                    SecureField("Being 完整连接地址", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(connecting ? "正在验证…" : "连接 Being") {
                        connecting = true
                        Task { if await store.connect(link) { link = ""; dismiss() }; connecting = false }
                    }.disabled(link.isEmpty || connecting)
                    if let error = store.notice { Text(error).font(.caption).foregroundStyle(.red) }
                } header: { Text("连接") }
                if let c = store.connection {
                    Section("当前连接") { LabeledContent("Being", value: c.being); Text(c.endpoint).font(.caption).foregroundStyle(ClientTheme.secondary); Button("断开连接", role: .destructive) { store.disconnect(); dismiss() } }
                    Section("模型") {
                        LabeledContent("服务商", value: provider.isEmpty ? "由 Being 管理" : provider)
                        LabeledContent("当前模型", value: model.isEmpty ? "正在读取…" : model)
                        HistoryLink("模型设置") { ModelSettingsView() }
                    }.task { if let data = try? await store.json(c, "/api/llm/config") { model = data["model"] as? String ?? "服务默认"; provider = data["provider"] as? String ?? "" } }
                }
                Section("Town") { Link(destination: URL(string: "https://beings.town")!) { Label("探索 Being Town", systemImage: "leaf") }; Text("小镇内容在系统浏览器中打开。").font(.caption).foregroundStyle(ClientTheme.secondary) }
                Section { LabeledContent("版本", value: "0.1 · Native"); Text("SwiftUI · iOS 26 Liquid Glass").font(.caption).foregroundStyle(ClientTheme.secondary) }
            }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle("连接与设置").toolbar { AdaptiveToolbar {  ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }  } }
        }
    }
}

private struct ThinkingIndicator: View {
    let activity: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Being").font(.caption).foregroundStyle(ClientTheme.secondary)
            TimelineView(.animation(minimumInterval: 0.2)) { context in
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Circle().fill(ClientTheme.secondary)
                            .frame(width: 6, height: 6)
                            .opacity(Int(context.date.timeIntervalSinceReferenceDate * 3) % 3 == index ? 1 : 0.3)
                    }
                    if activity != "思考中" { Text(activity).font(.caption).foregroundStyle(ClientTheme.secondary) }
                }.padding(.vertical, 10)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(activity)
    }
}
