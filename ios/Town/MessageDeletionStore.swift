import Foundation

extension Store {
    private var deletionFile: URL { URL.documentsDirectory.appending(path: "deleted-messages.json") }

    func loadMessageDeletions() {
        guard FileManager.default.fileExists(atPath: deletionFile.path) else { return }
        do { messageDeletions = try JSONDecoder().decode([MessageDeletion].self, from: Data(contentsOf: deletionFile)) }
        catch { messageDeletionsUnavailable = true; notice = "无法读取已删除消息记录，请恢复记录文件后再删除。" }
    }

    func isMessageDeleted(_ message: Message, endpoint: String) -> Bool {
        messageDeletions.contains { $0.matches(message, endpoint: endpoint) }
    }

    func canDeleteMessage(_ message: Message) -> Bool {
        guard !messageDeletionsUnavailable, message.role == "user" else { return false }
        if let entry = visibleOutbox.first(where: { $0.userID == message.id }) {
            return ["queued", "failed", "unknown", "stopped"].contains(entry.phase)
        }
        return message.files?.isEmpty == false || message.text.contains("[attachment-message:v1:")
    }

    func deleteMessage(_ message: Message) {
        guard canDeleteMessage(message), let endpoint = connection?.endpoint else { return }
        let entry = visibleOutbox.first { $0.userID == message.id }
        var removed = message
        if removed.sceneID == nil { removed.sceneID = entry?.sceneID }
        // Preparation can checkpoint a reference before the visible projection
        // updates; retain it so a later history response cannot resurrect it.
        if let entry, let reference = entry.attachmentMessageID, DeliveryRules.messageID(reference) {
            removed.text = "[attachment-message:v1:\(reference)]"
        }
        var next = messageDeletions
        next.append(MessageDeletion(removed, endpoint: endpoint))
        if let entry,
           let reply = conversations.first(where: { $0.endpoint == endpoint && $0.id == entry.sceneID })?.messages.first(where: { $0.id == entry.replyID && $0.sequence == nil }) {
            next.append(MessageDeletion(reply, endpoint: endpoint))
        }
        do {
            // Persist the tombstone first. On a crash, loadOutbox also drops
            // deleted entries before any delivery worker can restart them.
            try JSONEncoder().encode(next).write(to: deletionFile, options: [.atomic, .completeFileProtection])
            messageDeletions = next
            if let entry { changeQueued(entry.id, remove: true) }
        } catch { notice = "删除未能保存，请重试。" }
    }

    func deleteQueuedMessage(_ entry: PendingSend) {
        deleteMessage(Message(id: entry.userID, role: "user", text: entry.preparedText ?? entry.text, sceneID: entry.sceneID, files: entry.files, localBaseline: entry.baseline))
    }
}
