import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var social: SocialStore
    @State private var name = ""
    @State private var code = ""
    @State private var operation: Task<Void, Never>?
    @State private var working = false
    @State private var deadline: Task<Void, Never>?
    @State private var error: String?
    var body: some View {
        SettingsPage {
            SettingsSection(title: "小镇连接", icon: "link") {
                Label(social.status, systemImage: social.identity == nil ? "link" : "checkmark.shield")
                if let identity = social.identity {
                    LabeledContent("身份", value: identity.name.isEmpty ? identity.id : identity.name)
                    SettingsNote(text: identity.id)
                    Button("断开本机配对", role: .destructive) { social.unpair() }.disabled(working).frame(minHeight: 44)
                }
            }
            SettingsSection(title: "自动配对", icon: "sparkles") {
                SettingsNote(text: "使用当前 Being 获取配对码，连接你的小镇身份。")
                Button(working ? "正在连接…" : "自动连接 Town") {
                    run(auto: true) { let being = store.connection?.being ?? ""; let code = try await store.pairingCode(); try await social.pair(being, code) }
                }.buttonStyle(SettingsActionStyle()).disabled(working || store.busy || store.connection == nil)
                if working { Button("取消", role: .cancel) { operation?.cancel() }.frame(minHeight: 44) }
            }
            SettingsSection(title: "手动配对", icon: "keyboard") {
                TextField("Town ID 或 Being 名", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled().settingsInput()
                TextField("配对码", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled().settingsInput()
                Button("确认配对") { run { try await social.pair(name, code); code = "" } }
                    .buttonStyle(SettingsActionStyle()).disabled(working || name.isEmpty || code.count != 6)
            }
            SettingsSection(title: "已有凭据", icon: "key") { AdvancedPairing() }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }.navigationTitle("连接 Being Town")
            .onAppear { if name.isEmpty { name = store.connection?.being ?? "" } }.onDisappear { operation?.cancel() }
    }
    private func run(auto: Bool = false, _ action: @escaping @MainActor () async throws -> Void) {
        working = true; error = nil
        operation = Task { defer { working = false; deadline?.cancel() }; do { try await action() } catch { if !Task.isCancelled { self.error = error is PortalError ? error.localizedDescription : (auto ? "无法读取 Being 配对回复，请使用手动配对。" : "配对请求未完成，请检查网络；若配对码已失效，请获取新码。") } } }
        if auto { deadline = Task { do { try await Task.sleep(for: .seconds(90)); operation?.cancel(); error = "90 秒内未完成自动配对，请使用手动配对。" } catch {} } }
    }
}
struct SocialRow: Identifiable {
    var context: String?
    var id: String; var author: String; var recipient: String; var content: String; var date: String; var raw: [String: Any]
    init(_ data: [String: Any], index: Int, peers: [[String:Any]] = []) {
        context = ReplyRules.context(data,rows:peers)
        raw = data; id = field(data, "id", "seq", "message_id"); if id.isEmpty { id = "row-\(index)" }
        author = field(data, "sender_display", "sender_display_name", "speaker_name", "display_name", "sender_name", "sender", "town_id")
        recipient = field(data, "sender_town_id", "town_id", "sender_display", "sender_display_name")
        content = field(data, "content", "message"); date = field(data, "created_at", "at")
    }
}
struct SocialComposeTarget: Identifiable { let id = UUID(); let reply: SocialRow? }
struct SocialView: View {
    let kind: Destination
    @EnvironmentObject private var social: SocialStore
    @State private var rows: [SocialRow] = []
    @State private var rooms: [[String: Any]] = []
    @State private var roomID = ""
    @State private var roomTitle = ""
    @State private var mailbox = "all"
    @State private var search = ""
    @State private var filters = FeedFilter()
    @State private var limit = 100
    @State private var error: String?
    @State private var loading = false
    @State private var composeTarget: SocialComposeTarget?
    @State private var loadID = UUID()
    @State private var visible = false
    @State private var showMembers = false
    @State private var showFilters = false
    @State private var showAnnouncements = false
    init(kind: Destination, initialRoomID: String = "", initialRoomTitle: String = "") {
        self.kind = kind
        _roomID = State(initialValue: initialRoomID)
        _roomTitle = State(initialValue: initialRoomTitle)
    }
    private var roomList: Bool { kind == .firesides && roomID.isEmpty }
    private var hasFilters: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        (!roomList && (!filters.author.isEmpty || filters.relation != "all" || filters.days != 0 || filters.oldestFirst))
    }
    private var visibleRooms: [CatalogRecord] {
        rooms.filter { search.isEmpty || field($0, "name", "title").localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .compactMap { room in
                let id = field(room, "id", "fireside_id")
                return id.isEmpty ? nil : CatalogRecord(id: id, data: room)
            }
    }
    var body: some View {
        HistoryStack {
            Group {
                if social.identity == nil {
                    BeingEmptyState { Label("连接 Town，继续阅读", systemImage: kind.icon) }
                        description: { Text(ClientCopy.descriptions[kind.rawValue] ?? "") }
                        actions: { HistoryLink("配置 Town 连接") { PairingView() }.beingButton(prominent: true).foregroundStyle(ClientTheme.buttonText) }
                } else {
                    VStack(spacing: 0) {
                        feedToolbar
                        if kind == .mail {
                            SocialChoiceChips(options: [("all", "全部"), ("received", "收件箱"), ("sent", "已发送")], selection: $mailbox)
                                .padding(.horizontal, 20).padding(.bottom, 12)
                        }
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 20) {
                                    Color.clear.frame(height: 0).id("feed-top")
                                    if kind == .bonfire { AnnouncementStrip() }
                                    if roomList {
                                        ForEach(visibleRooms) { record in
                                            let room = record.data
                                            HistoryLink { SocialView(kind: kind, initialRoomID: field(room, "id", "fireside_id"), initialRoomTitle: field(room, "name", "title")) }
                                                label: { roomRow(room) }.buttonStyle(.plain)
                                        }
                                    } else {
                                        ForEach(filteredRows) { row in
                                            SocialMessageCard(row: row, kind: kind) { composeTarget = SocialComposeTarget(reply: row) }
                                        }
                                    }
                                    if let error {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text(error).font(.footnote).foregroundStyle(.red)
                                            Button("重试") { Task { await load() } }.frame(minHeight: 44)
                                        }
                                    }
                                    if loading { ProgressView().frame(maxWidth: .infinity).padding(24) }
                                    else if error == nil && (roomList ? visibleRooms.isEmpty : filteredRows.isEmpty) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text(hasFilters ? "没有匹配的内容" : roomList ? "暂无围炉" : "暂无消息")
                                                .foregroundStyle(ClientTheme.secondary)
                                            if hasFilters { Button("清除搜索与筛选") { search = ""; filters = FeedFilter() }.frame(minHeight: 44) }
                                        }.padding(.vertical, 20)
                                    }
                                }.frame(maxWidth: 680).padding(.horizontal, 20).padding(.bottom, 24)
                                    .frame(maxWidth: .infinity)
                            }.accessibilityIdentifier("socialFeed")
                                .refreshable { await load() }
                                .onChange(of: mailbox) { _ in proxy.scrollTo("feed-top", anchor: .top) }
                        }
                    }
                }
            }.background(ClientTheme.background).foregroundStyle(ClientTheme.text)
                .navigationTitle(roomList || roomID.isEmpty ? kind.title : roomTitle).navigationBarTitleDisplayMode(.inline)
                .onAppear { visible = true }
                .onDisappear { visible = false; loadID = UUID(); loading = false }
                .task(id: "\(social.identity?.id ?? "")|\(roomID)|\(mailbox)|\(limit)|\(social.revision)|\(visible)") {
                    if visible { await load() }
                }
                .onChange(of: social.identity?.id) { _ in rows = []; rooms = []; showMembers = false; composeTarget = nil; showFilters = false }
                .sheet(item: $composeTarget) { target in SocialComposer(kind: kind, roomID: roomID, roomTitle: roomTitle, reply: target.reply, sentMailbox: mailbox == "sent") { Task { await load() } } }
                .sheet(isPresented: $showMembers) { FiresideMembersView(roomID: roomID).presentationDetents([.medium, .large]) }
                .sheet(isPresented: $showFilters) {
                    SocialFilterSheet(roomList: roomList, kind: kind, search: $search, filters: $filters, limit: $limit)
                }
                .sheet(isPresented: $showAnnouncements) {
                    HistoryStack {
                        CatalogView(category: "announcements")
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showAnnouncements = false } } }
                    }.environment(\.pageHistory, nil)
                }
        }
    }
    private var feedToolbar: some View {
        HStack(spacing: 2) {
            Text(roomList ? "\(visibleRooms.count) 个围炉" : "\(filteredRows.count) 条消息")
                .font(.subheadline).foregroundStyle(ClientTheme.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            SocialAction(title: roomList ? "搜索围炉" : "搜索与筛选", icon: "magnifyingglass") { showFilters = true }
                .overlay(alignment: .topTrailing) {
                    if hasFilters { Circle().fill(ClientTheme.feedAction).frame(width: 6, height: 6).padding(7).allowsHitTesting(false) }
                }.accessibilityValue(hasFilters ? "已启用筛选" : "未筛选")
            SocialAction(title: "刷新", icon: "arrow.clockwise") { Task { await load() } }.disabled(loading)
            if !roomList {
                SocialAction(title: kind == .mail ? "写私信" : "写消息", icon: "square.and.pencil") { composeTarget = SocialComposeTarget(reply: nil) }
            }
            if kind == .bonfire || !roomID.isEmpty {
                Menu {
                    if kind == .bonfire { Button { showAnnouncements = true } label: { Label("小镇公告", systemImage: "megaphone") } }
                    if !roomID.isEmpty { Button { showMembers = true } label: { Label("围炉成员", systemImage: "person.2") } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("更多操作")
            }
        }.padding(.leading, 20).padding(.trailing, 8).padding(.bottom, 4)
            .frame(maxWidth: 720)
    }
    private func roomRow(_ room: [String: Any]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "person.2").font(.system(size: 22)).frame(width: 48, height: 48)
                .foregroundStyle(ClientTheme.fireInk).background(ClientTheme.fireTint, in: RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(field(room, "name", "title")).font(.body.weight(.medium)).lineLimit(2)
                let detail = field(room, "description", "topic")
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(ClientTheme.secondary).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            let unread = social.unread(firesideID: field(room, "id", "fireside_id"))
            if unread > 0 {
                Text(unread > 99 ? "99+" : String(unread))
                    .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
                    .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22)
                    .background(.red, in: Capsule())
                    .accessibilityLabel("\(unread) 条未读消息")
                    .accessibilityIdentifier("firesideUnread-" + field(room, "id", "fireside_id"))
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(ClientTheme.secondary).accessibilityHidden(true)
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
    private var filteredRows: [SocialRow] {
        let filtered = rows.filter { filters.matches($0.raw, me: social.identity?.id ?? "") && (search.isEmpty || $0.content.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search)) }
        return filters.oldestFirst ? Array(filtered.reversed()) : filtered
    }
    @MainActor private func load() async {
        guard visible else { return }
        guard social.identity != nil else { rows = []; rooms = []; return }
        let requestID = UUID(); loadID = requestID
        loading = true; error = nil; defer { if loadID == requestID { loading = false } }
        do {
            let path = kind == .bonfire ? "/api/bonfire/hear?limit=\(limit)" : kind == .mail ? "/api/messages?with=\(mailbox)" : roomID.isEmpty ? "/api/fireside/list" : "/api/fireside/hear?fireside_id=\(roomID)&limit=50"
            let data: [String: Any]
            if kind == .mail && mailbox == "all" {
                async let inbox = social.request("/api/messages?with=received")
                async let sent = social.request("/api/messages?with=sent")
                let (a, b) = try await (inbox, sent)
                var ids: Set<String> = []
                let combined = ((a["messages"] as? [[String: Any]] ?? []) + (b["messages"] as? [[String: Any]] ?? [])).filter { ids.insert(field($0,"id","message_id","seq")).inserted }
                data = ["messages": combined]
            } else { data = try await social.request(path) }
            try Task.checkCancellation(); guard loadID == requestID else { return }
            if kind == .firesides && roomID.isEmpty { var ids: Set<String> = []; rooms = ((data["owned"] as? [[String: Any]] ?? []) + (data["joined"] as? [[String: Any]] ?? [])).filter { ids.insert(field($0, "id", "fireside_id")).inserted } }
            else { rows = FeedRules.newestFirst(data["messages"] as? [[String: Any]] ?? []).enumerated().map { SocialRow($0.element, index: $0.offset, peers:data["messages"] as? [[String:Any]] ?? []) } }
            if kind == .firesides {
                social.acknowledge(firesideID: roomID, messages: data["messages"] as? [[String: Any]] ?? [])
            } else { social.acknowledge(kind) }
        } catch { if !Task.isCancelled && loadID == requestID { self.error = error is PortalError ? error.localizedDescription : "暂时无法读取，已有内容已保留。" } }
    }
}
struct SocialMessageCard: View {
    let row: SocialRow
    let kind: Destination
    let reply: () -> Void
    @State private var expanded = false
    private var long: Bool { row.content.count > 600 || row.content.components(separatedBy: "\n").count > 14 }
    private var author: String { row.author.isEmpty ? "Being" : row.author }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Text(String(author.prefix(1)).uppercased()).font(.system(size:17,weight:.medium))
                    .foregroundStyle(kind == .mail ? ClientTheme.feedAction : ClientTheme.fireInk)
                    .frame(width:40,height:40).background(kind == .mail ? ClientTheme.feedTint : ClientTheme.fireTint,in:Circle()).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text(author).font(.system(size:15,weight:.semibold)).lineLimit(1)
                    Text(String(row.date.prefix(16)).replacingOccurrences(of:"T",with:" ")).font(.system(size:12)).foregroundStyle(ClientTheme.secondary)
                }
                Spacer(minLength:0)
            }
            VStack(alignment:.leading,spacing:12) {
                if let context = row.context {
                    Text(context).font(.system(size:13)).foregroundStyle(ClientTheme.secondary).lineLimit(4)
                        .padding(.leading,12).overlay(alignment:.leading){Rectangle().fill(ClientTheme.feedAction.opacity(0.5)).frame(width:2)}
                }
                MarkdownText(text:row.content).tint(ClientTheme.feedAction)
                    .fixedSize(horizontal:false,vertical:true)
                    .frame(maxHeight:long && !expanded ? 248 : nil,alignment:.top).clipped()
                    .overlay(alignment:.bottom) {
                        if long && !expanded { LinearGradient(colors:[ClientTheme.socialCard(kind).opacity(0),ClientTheme.socialCard(kind)],startPoint:.top,endPoint:.bottom).frame(height:42).allowsHitTesting(false) }
                    }
                if long {
                    Button(expanded ? "收起全文" : "展开全文") { expanded.toggle() }
                        .font(.system(size:14,weight:.medium)).foregroundStyle(ClientTheme.feedAction).buttonStyle(.plain).frame(minHeight:32)
                }
            }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                .background(ClientTheme.socialCard(kind),in:RoundedRectangle(cornerRadius:24))
            HStack {
                Button(action:reply) { Label("让 Being 回复",systemImage:"arrowshape.turn.up.left").font(.system(size:13)).padding(.horizontal,12).frame(height:36) }
                    .buttonStyle(.plain).foregroundStyle(ClientTheme.feedAction).background(ClientTheme.feedTint,in:Capsule())
                Spacer()
                ShareLink(item:row.content) { Image(systemName:"square.and.arrow.up").font(.system(size:17)).frame(width:40,height:36) }
                    .buttonStyle(.plain).accessibilityLabel("分享")
            }.foregroundStyle(ClientTheme.feedAction)
        }.foregroundStyle(ClientTheme.text)
    }
}
struct SocialComposer: View {
    let kind: Destination; let roomID: String; let roomTitle: String; let reply: SocialRow?; let sentMailbox: Bool; let onSent: () -> Void
    var initialRecipient: String = ""
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: NavigationState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var recipient = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if kind == .mail { Section("收件 Being") { TextField("Town ID（t_…）或准确显示名", text: $recipient).textInputAutocapitalization(.never).autocorrectionDisabled() } }
                if let reply {
                    if let context = reply.context { Section("这条消息所回复的上文") { Text(context).font(.subheadline).foregroundStyle(ClientTheme.secondary) } }
                    Section("回复 \(reply.author)") { Text(reply.content).font(.subheadline).lineLimit(8).foregroundStyle(ClientTheme.secondary) }
                }
                Section(reply == nil ? "内容或给 Being 的描述" : "回复内容或给 Being 的要求") { TextEditor(text: $text).frame(minHeight: 180); Text("\(text.count) / \(kind == .bonfire ? 4000 : 32000)").font(.caption).foregroundStyle(ClientTheme.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Button(reply == nil ? "让 Being 发送" : "让 Being 回复") {
                        guard store.draft.isEmpty else { error = "对话中已有草稿，请先处理。"; return }
                        let place = kind == .firesides ? "围炉「\(roomTitle)」" : kind == .mail ? "与 \(recipient) 的私信" : "篝火"
                        store.draft = ReplyRules.prompt(place:place,author:reply?.author,content:reply?.content ?? "",context:reply?.context,description:text)
                        store.send()
                        nav.selected = "chat"; dismiss()
                    }.beingButton(prominent: true).foregroundStyle(ClientTheme.buttonText).disabled(store.connection == nil || store.busy || (reply == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || (kind == .mail && recipient.isEmpty))
                }
            }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle(kind == .mail ? (reply == nil ? "写私信" : "回复私信") : kind == .firesides ? "在围炉说一句" : "在篝火说一句")
                .toolbar { AdaptiveToolbar {  ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }; ToolbarItem(placement: .confirmationAction) { Button(busy ? "发送中…" : "发送") { Task { await send() } }.disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > (kind == .bonfire ? 4000 : 32000) || kind == .mail && recipient.isEmpty) }  } }
                .onAppear { if !initialRecipient.isEmpty { recipient = initialRecipient }; if let reply { recipient = (sentMailbox || field(reply.raw,"sender_town_id") == social.identity?.id) ? field(reply.raw, "recipient_town_id", "recipient_display", "recipient_display_name") : reply.recipient } }
                .interactiveDismissDisabled(busy)
        }
    }
    private func send() async {
        busy = true; error = nil; defer { busy = false }
        do {
            var body: [String: Any]; let path: String
            if kind == .mail { guard recipient != social.identity?.id else { throw PortalError.server("不能给自己发送私信。") }; path = "/api/messages"; body = ["recipient": recipient.trimmingCharacters(in: .whitespacesAndNewlines), "content": text]; if let reply { body["reply_to"] = reply.id } }
            else { path = kind == .bonfire ? "/api/bonfire/speak" : "/api/fireside/speak"; body = ["message": text]; if kind == .firesides { guard let id = Int(roomID), id > 0 else { throw PortalError.invalidResponse }; body["fireside_id"] = id }; if let reply, let seq = Int(field(reply.raw,"seq","id")) { body["reply_to"] = seq } }
            let response = try await social.request(path, body: body)
            guard response["ok"] as? Bool == true else { throw PortalError.invalidResponse }
            onSent(); dismiss()
        } catch { self.error = "未收到发送确认，消息可能已送达。请先刷新核对，避免重复发送。" }
    }
}

struct FiresideMembersView: View {
    let roomID: String
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss
    @State private var members: [FiresideMember] = []
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        NavigationStack {
            List {
                if loading { HStack { ProgressView(); Text("正在读取成员名单…").foregroundStyle(ClientTheme.secondary) } }
                if let error { Text(error).foregroundStyle(.red); Button("重试") { retry += 1 } }
                if !loading && error == nil && members.isEmpty { Text("暂无成员信息").foregroundStyle(ClientTheme.secondary) }
                ForEach(members) { member in
                    HStack(spacing: 14) {
                        Text(String(member.name.prefix(1))).font(.headline).frame(width: 44, height: 44)
                            .foregroundStyle(ClientTheme.fireInk).background(ClientTheme.fireTint, in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(member.name).foregroundStyle(ClientTheme.text)
                            if !member.townID.isEmpty && member.townID != member.name { Text(member.townID).font(.caption).foregroundStyle(ClientTheme.secondary).textSelection(.enabled) }
                            if !member.joinedAt.isEmpty { Text("加入 \(chatTime(member.joinedAt))").font(.caption).foregroundStyle(ClientTheme.secondary) }
                        }
                    }.padding(.vertical, 6).listRowBackground(ClientTheme.background)
                }
            }.scrollContentBackground(.hidden).background(ClientTheme.background).navigationTitle("成员名单")
                .toolbar { AdaptiveToolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } }
                .task(id: "\(roomID)|\(social.identity?.id ?? "")|\(retry)") {
                    loading = true; error = nil; members = []
                    defer { loading = false }
                    do {
                        guard roomID.range(of: "^[0-9]{1,16}$", options: .regularExpression) != nil else { throw PortalError.invalidResponse }
                        let response = try await social.request("/api/fireside/members?fireside_id=\(roomID)")
                        try Task.checkCancellation(); members = try TownContracts.members(response)
                    } catch { if !Task.isCancelled { self.error = "成员名单读取失败。" } }
                }
        }
    }
}
