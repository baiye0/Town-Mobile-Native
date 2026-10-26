import SwiftUI

@main struct TownApp: App {
    init() {
        _ = CompletionNotifications.shared
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--verify-keychain") { KeychainCheck.run() }
        #endif
    }
    @StateObject private var store = Store()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene { WindowGroup { MobileShell().environmentObject(store).buttonStyle(BeingDefaultButtonStyle()).toggleStyle(BeingToggleStyle()).background(ClientTheme.background).tint(ClientTheme.accent).preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil) } }
}
struct RootView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var phase
    @EnvironmentObject private var nav: NavigationState
    @State private var settings = false
    @StateObject private var speech = SpeechInput()
    @State private var actionsExpanded = false
    @State private var cameraRequested = false
    @State private var cameraPresented = false
    @State private var draftBeforeSpeech = ""
    @FocusState private var inputFocused: Bool
    @AppStorage("glassEffects") private var glass = true
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChatView(inputFocused: inputFocused, dismissKeyboard: { inputFocused = false })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                composer
            }
                .background { ClientTheme.background.ignoresSafeArea() }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { AdaptiveToolbar {
                    ToolbarItem(placement: .navigationBarLeading) { BeingIconButton("对话记录", systemImage: "line.3.horizontal") { withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { nav.sidebar = true } } }
                    ToolbarItem(placement: .principal) {
                        NavigationLink { ConversationSettingsView() } label: {
                            VStack(spacing: 0) {
                                Text(store.current?.title ?? "Being").font(.headline).lineLimit(1)
                                if store.connection != nil {
                                    HStack(spacing: 4) {
                                        SBSStatusDot(enabled: store.sbsEnabled == true, active: !store.sbsActivity.isEmpty)
                                        Text(store.sbsStatus).font(.caption2).foregroundStyle(ClientTheme.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }.buttonStyle(.plain).accessibilityLabel("打开对话设置")
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        BeingIconButton("刷新", systemImage:"arrow.clockwise") { Task { await store.history() } }.disabled(store.historyLoading || store.connection == nil)
                    }
                 } }

                .sheet(isPresented: $settings) { SettingsView() }
                .toolbar(inputFocused || !glass ? .hidden : .visible, for: .tabBar)
        }
        .sheet(isPresented: $actionsExpanded, onDismiss: {
            guard cameraRequested else { return }
            cameraRequested = false
            cameraPresented = true
        }) {
            AttachmentPickerRow {
                inputFocused = false
                cameraRequested = true
                actionsExpanded = false
            }
            .presentationDetents([.fraction(0.5)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $cameraPresented) {
            CameraCaptureView(onImage: { image in
                cameraPresented = false
                guard let data = image.jpegData(compressionQuality: 0.9) else {
                    store.notice = "照片保存失败，请重试。"
                    return
                }
                let url = URL.cachesDirectory.appending(path: "capture-\(UUID().uuidString).jpg")
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    try data.write(to: url)
                    store.importFiles([url])
                } catch { store.notice = error.localizedDescription }
            }, onCancel: { cameraPresented = false })
        }
        .task(id: "\(store.connection?.endpoint ?? "")|\(phase)|\(nav.selected)") {
            guard phase == .active, nav.selected == "chat", store.connection != nil else { return }
            await store.history()
            while !Task.isCancelled {
                await store.syncSBS()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
        .onChange(of: phase) { value in if value == .active { Task { await store.history() } } else if value == .background { speech.stop() } }
        .onChange(of: inputFocused) { value in nav.keyboardVisible = value }
        .onChange(of: nav.sidebar) { opened in if opened { inputFocused = false } }
        .onChange(of: nav.selected) { _ in inputFocused = false }
        .onChange(of: store.selected) { _ in inputFocused = false; speech.stop() }
        .onChange(of: store.connection?.endpoint) { _ in speech.stop() }
        .onDisappear { inputFocused = false; nav.keyboardVisible = false; speech.stop() }
    }
    private var composer: some View {
        ConversationComposer(input: store.composer, speech: speech,
                             actionsExpanded: $actionsExpanded, settings: $settings,
                             draftBeforeSpeech: $draftBeforeSpeech, inputFocused: $inputFocused)
    }
}

// Keystrokes publish only to the composer, not every historical message view.
private struct ConversationComposer: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var input: ComposerState
    @ObservedObject var speech: SpeechInput
    @Binding var actionsExpanded: Bool
    @Binding var settings: Bool
    @Binding var draftBeforeSpeech: String
    var inputFocused: FocusState<Bool>.Binding
    private var canInterrupt: Bool { store.busy && store.activeScene == store.selected && store.streamID != nil }

    var body: some View {
        return VStack(spacing: 8) {
            if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.red).padding(.horizontal).accessibilityAddTraits(.updatesFrequently) }
            if store.intelligentUISelection != nil && store.intelligentUI {
                HStack {
                    Label("已带入智能界面和当前选择", systemImage: "slider.horizontal.3").font(.caption)
                    Spacer()
                    Button("移除") { store.intelligentUISelection = nil }.font(.caption)
                }.padding(.horizontal, 18).accessibilityIdentifier("intelligentUISelection")
            }
            AdaptiveGlassContainer(spacing: 12) {
                VStack(spacing: 0) {
                    // Muse keeps selected images in the composer itself. This makes
                    // the attachment visible after the picker is dismissed and keeps
                    // the send action in the same, predictable surface.
                    AttachmentPreviewStrip()
                    Group {
                        if speech.active {
                            VoiceInputBar(speech: speech, cancel: {
                                speech.stop(); input.draft = draftBeforeSpeech
                            })
                        } else {
                            HStack(alignment: .center, spacing: 8) {
                                Button { withAnimation { actionsExpanded.toggle() } } label: { Image(systemName: actionsExpanded ? "xmark" : "plus").font(.system(size: 21)).frame(width: 40, height: 44) }.accessibilityLabel(actionsExpanded ? "收起资源库" : "展开资源库")
                                TextField("说点什么…", text: $input.draft, axis: .vertical)
                                    .focused(inputFocused).lineLimit(1...6).disabled(speech.active).font(.system(size: 16)).padding(.vertical, 10).accessibilityLabel("消息")
                                Button {
                                    inputFocused.wrappedValue = false
                                    if speech.active { speech.finish() }
                                    else {
                                        let original = input.draft
                                        draftBeforeSpeech = original
                                        Task { await speech.start(update: { text in input.draft = original + (original.isEmpty ? "" : " ") + text },failure: { store.notice = $0 }) }
                                    }
                                } label: {
                                    Image(systemName:speech.active ? "stop.circle.fill" : "mic").font(.system(size:20)).frame(width:40,height:44)
                                        .foregroundStyle(speech.active ? Color.red : ClientTheme.secondary)
                                }.accessibilityLabel(speech.active ? "停止语音输入" : "语音输入").disabled(store.busy)
                                if canInterrupt && (!input.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.attachments.isEmpty) {
                                    Button("排队") { store.send() }.font(.caption).accessibilityLabel("加入队列")
                                }
                                if store.busy || store.connection == nil || !input.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !store.attachments.isEmpty {
                                Button {
                                    if store.connection == nil { inputFocused.wrappedValue = false; settings = true }
                                    else if store.busy && input.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachments.isEmpty { Task { await store.stop() } }
                                    else { store.send(interrupt: true) }
                                } label: {
                                    Image(systemName: store.busy && input.draft.isEmpty && store.attachments.isEmpty ? "stop.fill" : store.connection == nil ? "link" : "arrow.up")
                                        .font(.system(size: 18, weight: .semibold)).frame(width: 36, height: 36)
                                        .foregroundStyle(ClientTheme.buttonText).background(ClientTheme.accent, in: Circle())
                                }.accessibilityLabel(store.connection == nil ? "连接 Being" : store.busy && input.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachments.isEmpty ? "停止生成" : store.busy ? (canInterrupt ? "立即发送" : "加入队列") : "发送")
                                    .disabled(speech.active || (store.connection != nil && !store.busy && input.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachments.isEmpty))
                                    .frame(width: 44, height: 44)
                                }
                            }.padding(.trailing, 6)
                        }
                    }
                    .frame(minHeight: 48)
                }
                .beingSurface(radius: 24)
                .padding(.horizontal, 16)
            }
        }.padding(.top, 12).padding(.bottom, inputFocused.wrappedValue ? 8 : 10)
    }
}
struct VoiceInputBar: View {
    @ObservedObject var speech: SpeechInput
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
    var inputFocused = false
    var dismissKeyboard: () -> Void = {}
    @State private var showConnection = false
    @State private var nearBottom = true
    @State private var followLatest = true
    @State private var userScrolling = false
    @State private var bottomRequest = 0
    @State private var legacyScrollMetrics = LegacyChatScrollMetrics()
    @State private var legacyViewportHeight: CGFloat = 0
    @State private var replyFillsViewport = false
    @State private var replyAnchored = false
    @State private var showIndex = false
    @State private var indexSearch = ""
    @State private var jumpID: UUID?
    @EnvironmentObject private var store: Store
    var body: some View {
        let allMessages = store.displayMessages
        let messages = allMessages
        let lastUserIndex = messages.lastIndex(where: { $0.role == "user" }) ?? -1
        ScrollViewReader { proxy in
            ScrollView {
                if !messages.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            VStack(alignment: .leading, spacing: 8) {
                            if let time = message.timestamp, index == 0 || messages[index - 1].timestamp?.prefix(16) != time.prefix(16) {
                                Text(chatTime(time)).font(.caption2).foregroundStyle(ClientTheme.secondary).frame(maxWidth:.infinity).padding(.vertical,4)
                            }
                            if message.kind == "marker" { HStack { Rectangle().frame(height:1); Text(message.text).font(.caption); Rectangle().frame(height:1) }.foregroundStyle(ClientTheme.secondary).padding(.vertical,8) }
                            else {
                                let isUser = message.role == "user"
                                let isGlobalBeingMessage = message.sceneID == nil && message.role == "being" && message.kind == nil
                                let hasAttachment = isUser && (!((message.files ?? []).isEmpty) || message.text.contains("[attachment-message:v1:"))
                                let originalText = hasAttachment ? DeliveryRules.displayText(message.text).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                                HStack(alignment: .center, spacing: 4) {
                                    if isUser {
                                        Spacer(minLength: 16)
                                        DeliveryStatusView(message: message)
                                    }
                                    if hasAttachment {
                                        VStack(alignment: .trailing, spacing: 8) {
                                            VStack(alignment: .trailing, spacing: 9) {
                                                if (store.showAllScenes && message.sceneID != store.selected) || isGlobalBeingMessage {
                                                    Text(isGlobalBeingMessage ? "全局消息" : store.sceneName(message))
                                                        .font(.caption)
                                                        .foregroundStyle(ClientTheme.secondary)
                                                        .lineLimit(1)
                                                        .truncationMode(.tail)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                }
                                                AttachmentMessageView(message: message, foreground: ClientTheme.text, attachmentCards: true).tint(ClientTheme.accent)
                                            }

                                            if !originalText.isEmpty {
                                                MarkdownText(text: originalText, foreground: .white, fillsWidth: false)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 12)
                                                    .background(ClientTheme.chatSent, in: RoundedRectangle(cornerRadius: 22))
                                            }
                                        }
                                        .contextMenu {
                                            ShareLink(item: originalText.isEmpty ? DeliveryRules.displayText(message.text) : originalText)
                                            Button("引用到草稿") {
                                                let value = originalText.isEmpty ? DeliveryRules.displayText(message.text) : originalText
                                                store.draft += (store.draft.isEmpty ? "" : "\n\n") + value.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
                                            }
                                            BeingIconButton("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = originalText.isEmpty ? DeliveryRules.displayText(message.text) : originalText }
                                            if store.canDeleteMessage(message) { BeingIconButton("删除", systemImage: "trash", role: .destructive) { store.deleteMessage(message) } }
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 9) {
                                            if (store.showAllScenes && message.sceneID != store.selected) || isGlobalBeingMessage {
                                                Text(isGlobalBeingMessage ? "全局消息" : store.sceneName(message))
                                                    .font(.caption)
                                                    .foregroundStyle(isUser ? .white : ClientTheme.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            AttachmentMessageView(message: message, foreground: isUser ? .white : ClientTheme.text).tint(isUser ? .white : ClientTheme.accent)
                                        }.padding(16)
                                            .background(isUser ? ClientTheme.chatSent : ClientTheme.chatReply, in: RoundedRectangle(cornerRadius: 22))
                                            .contextMenu {
                                                ShareLink(item: DeliveryRules.displayText(message.text))
                                                Button("引用到草稿") { store.draft += (store.draft.isEmpty ? "" : "\n\n") + DeliveryRules.displayText(message.text).split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n") }
                                                BeingIconButton("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = DeliveryRules.displayText(message.text) }
                                                if store.canDeleteMessage(message) { BeingIconButton("删除", systemImage: "trash", role: .destructive) { store.deleteMessage(message) } }
                                            }
                                    }
                                    if !isUser { Spacer(minLength: 24) }
                                }
                                if isUser {
                                    let running = store.busy && store.outbox.contains {
                                        $0.id == store.activeSendID && $0.userID == message.id && $0.endpoint == store.connection?.endpoint
                                    }
                                    if running || message.process?.isEmpty == false {
                                        ChatRunView(process: message.process ?? "", activity: store.activity, isActive: running)
                                    }
                                }
                            }
                            }.id(message.id)
                                .modifier(StreamReplyGeometry(tracked: message.id == store.streamingReplyID &&
                                    index > lastUserIndex,
                                    viewportHeight: legacyViewportHeight, fillsViewport: $replyFillsViewport))
                        }
                        if store.historyLoading { ProgressView() }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(24).modifier(LegacyChatContentGeometry(viewportHeight: legacyViewportHeight,
                                                                   metrics: $legacyScrollMetrics))
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        Image("ClientLogo").resizable().scaledToFit().frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityHidden(true)
                            .padding(.top, 36)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.connection == nil ? "从一个想法开始" : "Being").font(.largeTitle.weight(.medium))
                            Text(store.connection == nil ? "连接你的 Being，继续对话。" : "当前场景还没有对话。").font(.subheadline).foregroundStyle(ClientTheme.secondary)
                            if store.connection == nil { Button("连接我的 Being") { showConnection = true }
                                    .buttonStyle(SettingsActionStyle()).frame(maxWidth: 280).padding(.top, 16) }
                        }
                    }.frame(maxWidth: 520, alignment: .leading).padding(.horizontal, 28).padding(.bottom, 20).frame(maxWidth: .infinity)
                }
            }.accessibilityIdentifier("chatMessageList")
                .scrollDismissesKeyboard(.interactively)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { legacyViewportHeight = $0 }
                .onChange(of: inputFocused) { focused in
                    guard focused else { return }
                    // Starting to compose explicitly returns to the latest turn,
                    // even when the user was reading older messages.
                    replyAnchored = false
                    replyFillsViewport = false
                    userScrolling = false
                    followLatest = true
                    bottomRequest += 1
                }
                .onChange(of: legacyViewportHeight) { _ in
                    // Focus arrives before the keyboard finishes resizing the
                    // viewport. Also keep the tail visible as the draft grows.
                    if inputFocused, followLatest, !userScrolling { bottomRequest += 1 }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    // UIKit can finish its inset adjustment after SwiftUI's
                    // geometry update, especially on iOS 16.
                    if inputFocused, followLatest, !userScrolling { bottomRequest += 1 }
                }
                .onChange(of: replyFillsViewport) { full in
                    guard full, !inputFocused, followLatest, !userScrolling, let id = store.streamingReplyID else { return }
                    // Like Town-Client, keep the beginning of a long reply in
                    // view once it fills the viewport instead of chasing tokens.
                    replyAnchored = true; followLatest = false
                    proxy.scrollTo(id, anchor: .top)
                }
                .onChange(of: userScrolling) { scrolling in if scrolling { replyAnchored = false } }
                .onChange(of: store.streamingReplyID) { id in
                    replyFillsViewport = false
                    if id != nil, replyAnchored { replyAnchored = false; followLatest = true; bottomRequest += 1 }
                }
                .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
                .modifier(ChatScrollBehavior(nearBottom: $nearBottom, followLatest: $followLatest,
                                             userScrolling: $userScrolling, bottomRequest: $bottomRequest,
                                             legacyMetrics: legacyScrollMetrics, viewportHeight: $legacyViewportHeight))
                .task(id: bottomRequest) {
                    guard bottomRequest > 0, followLatest, !userScrolling else { return }
                    await Task.yield()
                    guard !Task.isCancelled, followLatest, !userScrolling else { return }
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: jumpID) { id in
                    guard let id, allMessages.contains(where: { $0.id == id }) else { return }
                    followLatest = false
                    Task { @MainActor in await Task.yield(); proxy.scrollTo(id, anchor: .top); jumpID = nil }
                }
                .onChange(of: allMessages.count) { _ in if followLatest { bottomRequest += 1 } }
                .onChange(of: store.selected) { _ in replyAnchored = false; followLatest = true; bottomRequest += 1 }
                .onChange(of: store.showAllScenes) { _ in followLatest = true; bottomRequest += 1 }
                .onChange(of: store.submittedMessageID) { id in
                    if id != nil { replyAnchored = false; replyFillsViewport = false; followLatest = true; bottomRequest += 1 }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !nearBottom && !messages.isEmpty {
                        Button { replyAnchored = false; userScrolling = false; followLatest = true; bottomRequest += 1 } label: {
                            Image(systemName: "arrow.down").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        }.beingButton().beingCircleButtonShape().accessibilityLabel("回到底部").padding(16)
                    }
                }
        }.overlay(alignment: .topTrailing) { if !allMessages.isEmpty { BeingIconButton("提问索引", systemImage: "list.bullet") { showIndex = true }.labelStyle(.iconOnly).padding(12).background(ClientTheme.background, in: Circle()).padding(8) } }
            .sheet(isPresented: $showIndex) { NavigationStack { List(allMessages.reversed().filter { $0.role == "user" && (indexSearch.isEmpty || $0.text.localizedCaseInsensitiveContains(indexSearch)) }) { message in Button { jumpID = message.id; showIndex = false } label: {
                let prompt = DeliveryRules.displayText(message.text).trimmingCharacters(in: .whitespacesAndNewlines)
                Text(prompt.isEmpty ? "附件消息" : prompt).lineLimit(3)
            } }.searchable(text: $indexSearch, prompt: "搜索提问").navigationTitle("提问索引").toolbar { Button("完成") { showIndex = false } } } }
        .background(ClientTheme.background).sheet(isPresented: $showConnection) { SettingsView() }
    }
}
private struct DeliveryStatusView: View {
    let message: Message
    @EnvironmentObject private var store: Store
    private var entry: PendingSend? { store.outbox.first { $0.userID == message.id && $0.endpoint == store.connection?.endpoint } }
    var body: some View {
        if let entry {
            if DeliveryRules.showsRetry(entry.phase) {
                Button { store.retryQueued(entry.id) } label: {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 22))
                        .foregroundStyle(.red).frame(width: 44, height: 44)
                }.buttonStyle(.plain)
                    .disabled(entry.phase == "unknown" && store.busy)
                    .accessibilityLabel("重试发送")
                    .accessibilityHint(entry.error ?? "消息未发送成功，点击重试")
                    .accessibilityIdentifier("retryMessage")
            }
        }
    }
}
func chatTime(_ value:String) -> String {
    let fractional=ISO8601DateFormatter(); fractional.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
    guard let date=fractional.date(from:value) ?? ISO8601DateFormatter().date(from:value) else{return String(value.replacingOccurrences(of:"T",with:" ").prefix(16))}
    let format=DateFormatter();format.dateStyle = Calendar.current.isDateInToday(date) ? .none : .medium;format.timeStyle = .short
    return format.string(from:date)
}
struct HistoryView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                BeingIconButton("开启新对话", systemImage: "plus") { store.newChat(); dismiss() }.disabled(store.connection == nil)
                ForEach(store.rooms.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { room in
                    Button { store.selectScene(room.id); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(room.title).foregroundStyle(ClientTheme.text); Text(room.updated, style: .date).font(.caption).foregroundStyle(ClientTheme.secondary) }.padding(.vertical, 6)
                    }.swipeActions { Button("删除本地记录", role: .destructive) { store.delete(room.id) } }
                }
            }.overlay { if store.rooms.isEmpty { BeingEmptyState("暂无对话记录。", systemImage: "bubble.left.and.bubble.right") } }
                .searchable(text: $query, prompt: "搜索对话")
                .refreshable { await store.history() }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle("对话")
                .toolbar { AdaptiveToolbar {  ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }  } }
        }.task { await store.history() }
    }
}
// Connection sheets and pushed settings share content without nesting navigation bars.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            BeingConnectionView()
                .toolbar { AdaptiveToolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                } }
        }
    }
}

struct BeingConnectionView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var connecting = false
    var body: some View {
        SettingsPage {
            SettingsSection(title: "连接你的 Being", icon: "sparkles") {
                SettingsNote(text: "粘贴完整连接地址，继续与你的 Being 对话。")
                SecureField("Being 完整连接地址", text: $link)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().settingsInput()
                Button(connecting ? "正在验证…" : "连接 Being") {
                    connecting = true
                    Task { if await store.connect(link) { link = ""; dismiss() }; connecting = false }
                }.buttonStyle(SettingsActionStyle()).disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting)
                if let error = store.notice { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            if let connection = store.connection {
                SettingsSection(title: "当前连接", icon: "checkmark.shield") {
                    LabeledContent("Being", value: connection.being)
                    Text(connection.endpoint).font(.footnote).foregroundStyle(ClientTheme.secondary).textSelection(.enabled)
                    Button("断开连接", role: .destructive) { store.disconnect(); dismiss() }
                        .frame(minHeight: 44)
                }
                SettingsCard {
                    HistoryLink { ModelSettingsView() } label: {
                        SettingsRow(title: "模型设置", icon: "cpu", subtitle: "线路、模型与思考深度")
                    }.buttonStyle(.plain)
                }
            }
            SettingsCard {
                Link(destination: URL(string: "https://beings.town")!) {
                    SettingsRow(title: "探索 Being Town", icon: "leaf", subtitle: "在浏览器中打开小镇")
                }.buttonStyle(.plain)
            }
        }.navigationTitle("连接 Being")
    }
}

struct SBSControlView: View {
    @EnvironmentObject private var store: Store
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { expanded.toggle() } label: {
                HStack {
                    SBSStatusDot(enabled: store.sbsEnabled == true, active: !store.sbsActivity.isEmpty)
                    Text(store.sbsStatus).font(.caption).lineLimit(2)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                }.foregroundStyle(ClientTheme.text).frame(minHeight: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("SBS 状态与显示设置，" + store.sbsStatus)
            if expanded {
                Toggle("显示 SBS 消息正文", isOn: Binding(get: { store.showAllScenes || store.showSBS }, set: { store.showSBS = $0; store.saveSBS() })).disabled(store.showAllScenes || store.current == nil)
                Text(store.showAllScenes ? "全部场景包含 SBS 正文；切回当前场景后恢复该场景的设置。" : "仅影响当前场景，思考状态统一在顶部显示。").font(.caption).foregroundStyle(ClientTheme.secondary)
                Toggle("自主醒来", isOn: Binding(get: { store.sbsEnabled ?? false }, set: { value in Task { await store.setSBSEnabled(value) } })).disabled(store.sbsEnabled == nil || store.sbsUpdating)
                Text("控制 SBS 是否主动开始任务").font(.caption).foregroundStyle(ClientTheme.secondary)
                if let error = store.sbsError { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.font(.subheadline)
    }
}
