import SwiftUI

@MainActor final class LiveReplyState: ObservableObject {
    @Published private(set) var message: Message
    init(_ message: Message) { self.message = message }
    func update(_ value: Message) { if message != value { message = value } }
}

// Keep scroll proximity, keyboard and toolbar state outside the history's
// ForEach. Equal snapshots share array storage; live reply objects still update
// their own rows, and environment changes continue to reach the descendants.
struct ChatMessageRows: View, Equatable {
    let store: Store
    let messages: [Message]
    let streamingReplyID: UUID?
    let viewportHeight: CGFloat
    let historyLoading: Bool
    @Binding var replyFillsViewport: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.store === rhs.store && lhs.messages == rhs.messages &&
            lhs.streamingReplyID == rhs.streamingReplyID && lhs.viewportHeight == rhs.viewportHeight &&
            lhs.historyLoading == rhs.historyLoading
    }

    var body: some View {
        let lastUserIndex = messages.lastIndex(where: { $0.role == "user" }) ?? -1
        // The lazy container itself must stay inside this update boundary.
        // Wrapping only its ForEach would hide the row count from LazyVStack.
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                VStack(alignment: .leading, spacing: 8) {
                    if let time = message.timestamp, index == 0 || messages[index - 1].timestamp?.prefix(16) != time.prefix(16) {
                        Text(chatTime(time)).font(.caption2).foregroundStyle(ClientTheme.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    LiveChatMessageRow(state: store.liveReply(for: message), snapshot: message)
                }.id(message.id)
                    .modifier(StreamReplyGeometry(tracked: message.id == streamingReplyID && index > lastUserIndex,
                                                  viewportHeight: viewportHeight, fillsViewport: $replyFillsViewport))
            }
            if historyLoading { ProgressView() }
            Color.clear.frame(height: 1).id("bottom")
        }.padding(24)
    }
}

struct LiveChatMessageRow: View {
    @ObservedObject var state: LiveReplyState
    let snapshot: Message
    // Keep one view identity across completion, but use the list's canonical
    // snapshot for static rows (including display-only scene/history metadata).
    var body: some View {
        ChatMessageRow(message: snapshot.streaming == true ? state.message : snapshot)
    }
}

struct ChatMessageRow: View {
    let message: Message
    @EnvironmentObject private var store: Store
    var body: some View {
        Group {
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
                    if running {
                        ActiveChatRunView(progress: store.runProgress)
                    } else if message.process?.isEmpty == false {
                        ChatRunView(process: message.process ?? "", activity: "", isActive: false)
                    }
                }
            }
        }
    }
}
