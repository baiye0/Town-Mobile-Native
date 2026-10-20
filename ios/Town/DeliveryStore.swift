import Foundation
import UIKit

extension Store {
    var outboxFile: URL { URL.documentsDirectory.appending(path: "outbox.json") }
    var visibleOutbox: [PendingSend] { outbox.filter { $0.endpoint == connection?.endpoint } }
    func loadOutbox() {
        guard let data = try? Data(contentsOf: outboxFile) else { return }
        do {
            outbox = try JSONDecoder().decode([PendingSend].self, from: data)
            let count = outbox.count
            outbox.removeAll { entry in
                isMessageDeleted(Message(id: entry.userID, role: "user", text: entry.preparedText ?? entry.text, sceneID: entry.sceneID), endpoint: entry.endpoint)
            }
            if outbox.count != count { try saveOutbox() }
        }
        catch { outboxUnavailable = true; notice = "发送队列无法读取，已保留原文件；请先恢复队列文件。" }
    }
    func saveOutbox() throws { try OutboxCheckpoint.save(outbox, to: outboxFile) }
    func send(interrupt: Bool = false) {
        guard !outboxUnavailable, let c = connection else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        if current == nil { newChat() }
        guard let room = current else { return }
        var entry = PendingSend(endpoint: c.endpoint, sceneID: room.id, title: room.title, text: text, files: attachments, baseline: timeline.compactMap(\.sequence).max() ?? 0)
        let timestamp = ISO8601DateFormatter()
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        entry.createdAt = timestamp.string(from: Date())
        entry.afterID = room.messages.last?.id
        entry.intelligentUI = intelligentUI
        outbox.append(entry)
        do {
            try saveOutbox()
            // The worker may be busy or blocked by an uncertain send. Project
            // the durable queue entry before clearing the composer either way.
            project(entry); persist(); submittedMessageID = entry.userID
            draft = ""; attachments = []; intelligentUI = false
            if interrupt, busy, activeScene == room.id, streamID != nil {
                Task { await interruptQueued(entry.id) }
            } else { startDelivery() }
        }
        catch { outbox.removeAll { $0.id == entry.id }; notice = "无法保存发送队列，草稿已保留。" }
    }
    func changeQueued(_ id: String, text: String? = nil, move: Int = 0, remove: Bool = false) {
        guard let i = outbox.firstIndex(where: { $0.id == id }), outbox[i].phase == "queued" || outbox[i].phase == "failed" || outbox[i].phase == "unknown" || outbox[i].phase == "stopped" else { return }
        let old = outbox
        let changed = outbox[i]
        if remove { outbox.remove(at: i) }
        else if DeliveryRules.canEdit(outbox[i].phase) {
            if let text, outbox[i].files.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { outbox[i].text = text; outbox[i].preparedText = nil }
            if move != 0 {
                let peers = outbox.indices.filter { outbox[$0].endpoint == outbox[i].endpoint && outbox[$0].phase == "queued" }
                if let p = peers.firstIndex(of: i), peers.indices.contains(p + move) { outbox.swapAt(i, peers[p + move]) }
            }
        }
        do {
            try saveOutbox()
            if remove {
                if let room = conversations.firstIndex(where: { $0.id == changed.sceneID && $0.endpoint == changed.endpoint }) {
                    conversations[room].messages.removeAll { $0.sequence == nil && ($0.id == changed.userID || $0.id == changed.replyID || $0.replyTo == changed.userID) }
                }
            } else if let entry = outbox.first(where: { $0.id == id }) { project(entry) }
            persist()
            if remove && notice == "发送未完成，请查看发送队列。" && !visibleOutbox.contains(where: { ["failed", "unknown"].contains($0.phase) }) { notice = nil }
            startDelivery()
        } catch { outbox = old; notice = "无法保存队列修改。" }
    }
    func retryQueued(_ id: String) {
        guard let i = outbox.firstIndex(where: { $0.id == id }), DeliveryRules.canRetry(outbox[i].phase) else { return }
        outbox[i].phase = "queued"; outbox[i].error = nil
        for j in outbox[i].files.indices where outbox[i].files[j].attachmentID != nil && outbox[i].files[j].jobID == nil { outbox[i].files[j].forceParse = true }
        do { try saveOutbox(); startDelivery() } catch { outbox[i].phase = "failed"; notice = "无法保存发送状态。" }
    }
    func resumeDelivery() {
        guard worker == nil else { return }
        // A restart never repeats a POST whose outcome is unknown.
        startDelivery(recover: true)
    }
    func startDelivery(recover: Bool = false) {
        guard !outboxUnavailable, !messageDeletionsUnavailable, worker == nil, !busy, let c = connection else { return }
        // A failed or explicitly stopped item is no longer a runnable queue
        // head. It must not prevent a later queued message from being sent.
        // An unknown/sending item still blocks the endpoint until it is
        // reconciled or removed, preventing an accidental duplicate turn.
        let endpointItems = outbox.enumerated().filter { $0.element.endpoint == c.endpoint }
        var head = 0
        while head < endpointItems.count && ["failed", "stopped"].contains(endpointItems[head].element.phase) { head += 1 }
        guard head < endpointItems.count else { return }
        let first = endpointItems[head].element
        guard !isMessageDeleted(Message(id: first.userID, role: "user", text: first.preparedText ?? first.text, sceneID: first.sceneID), endpoint: c.endpoint) else { return }
        guard ["queued", "preparing"].contains(first.phase) || recover && ["sending", "waiting", "unknown"].contains(first.phase) else { return }
        busy = true; activeScene = first.sceneID; activeSendID = first.id
        worker = Task {
            var safeToContinue = false
            // Always attempt a drain after the worker exits. startDelivery()
            // skips failed/stopped heads and still refuses to pass an unknown
            // result, so a retryable failure cannot strand later messages.
            defer { busy = false; activeScene = nil; activeSendID = nil; streamID = nil; streamingReplyID = nil; activity = ""; worker = nil; persist(); startDelivery() }
            guard let index = outbox.firstIndex(where: { $0.id == first.id }) else { return }
            var entry = outbox[index]
            @MainActor func checkpoint(background: Bool = false) throws {
                guard let i = outbox.firstIndex(where: { $0.id == entry.id }) else { throw CancellationError() }
                outbox[i] = entry
                if background {
                    OutboxCheckpoint.schedule(outbox, to: outboxFile) { [weak self] in
                        Task { @MainActor in self?.notice = "回复恢复状态未能保存，请检查设备存储空间。" }
                    }
                } else { try saveOutbox() }
            }
            do {
                if ["queued", "preparing"].contains(entry.phase) {
                    entry.phase = "preparing"; try checkpoint()
                    entry.preparedText = nil
                    activity = "思考中"
                    // Town Client projects the user turn before any upload starts.
                    // Keep the local files attached to that same bubble while
                    // upload and parsing continue in the background.
                    project(entry)
                    if !entry.files.isEmpty {
                        entry.preparedText = try await prepareFiles(&entry, connection: c)
                    }
                    if entry.intelligentUI == true { entry.preparedText = (entry.preparedText ?? entry.text) + NativeUI.context }
                    entry.baseline = try await historyBaseline(c, after: entry.baseline)
                    if let id = entry.attachmentMessageID { _ = try await attachmentJSON(c, "/api/attachment-messages/\(id)", body: ["delivery_status":"sending"]) }
                    entry.phase = "sending"; try checkpoint()
                    project(entry)
                    let request = request(c, "/api/chat/stream", method: "POST", body: ["message": entry.preparedText ?? entry.text, "scene_id": entry.sceneID, "scene_meta": ["client": "being-ios/0.3", "scene_label": entry.title]])
                    do {
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse else { throw PortalError.invalidResponse }
                        if let id = entry.attachmentMessageID { _ = try? await attachmentJSON(c, "/api/attachment-messages/\(id)", body: ["delivery_status": (200..<300).contains(http.statusCode) ? "accepted" : (400..<500).contains(http.statusCode) ? "failed" : "unknown"]) }
                        if http.statusCode == 202 { entry.phase = "waiting"; try checkpoint() }
                        else {
                            guard http.statusCode == 200 else {
                                if (400..<500).contains(http.statusCode) { entry.phase = "failed" }
                                throw PortalError.http(http.statusCode)
                            }
                            guard http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else { throw PortalError.invalidResponse }
                            var completed = false
                            let presentation = StreamPresentation { [weak self] in self?.project($0) }
                            defer { presentation.flush() }
                            var lastSaved = Date.distantPast
                            @MainActor func handle(_ event: SSEEvent) throws {
                                if event.data == "[DONE]" { completed = true; return }
                                guard let value = event.payload else { return }
                                let type = event.name == "message" ? value["type"] as? String ?? "message" : event.name
                                if DeliveryRules.countsForReplay(type, continuation: value["continuation"] as? Bool == true, persisted: value["persisted"] != nil) { entry.cursor += 1 }
                                try consume(type, value, entry: &entry)
                                if value["scene_id"] != nil && value["scene_id"] as? String != entry.sceneID { return }
                                if ["done", "end"].contains(type) { completed = true }
                                // message_stop closes one reply bubble, not the
                                // whole turn. EOF/[DONE] is the turn boundary.
                                else if ["text", "content_block_delta", "tool_use", "thinking", "reasoning"].contains(type) { completed = false }
                                presentation.submit(entry)
                            }
                            try await SSETransport.read(bytes) { event in
                                try handle(event)
                                if Date().timeIntervalSince(lastSaved) > 0.5 { try checkpoint(background: true); lastSaved = Date() }
                            }
                            ReplyStream.finish(&entry)
                            presentation.submit(entry)
                            // A clean close flushes the final partial frame. Tool
                            // progress alone does not confirm a completed answer.
                            if !completed && ReplyStream.hasFinalReply(entry) { completed = true }
                            if completed && ReplyStream.hasFinalReply(entry) { safeToContinue = true }
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch { if entry.phase == "failed" { throw error }; activity = "正在恢复连接" }
                }
                if !safeToContinue { project(entry); safeToContinue = try await self.recover(&entry, connection: c) }
                if safeToContinue {
                    _ = try? await reconcile(&entry, connection: c)
                    guard persist() else { throw PortalError.server("无法保存已完成的回复") }
                    let previous = outbox
                    outbox.removeAll { $0.id == entry.id }; do { try saveOutbox() } catch { outbox = previous; throw error }
                    if notice == "发送未完成，请查看发送队列。" { notice = nil }
                    CompletionNotifications.shared.finished(endpoint: c.endpoint, scene: entry.sceneID, title: entry.title, shouldNotify: !appActive || !chatVisible || selected != entry.sceneID)
                } else { entry.phase = "unknown"; entry.error = "发送结果待确认；可同步历史或移除本地等待记录，不会自动重发。"; try checkpoint() }
            } catch is CancellationError {
                if let i = outbox.firstIndex(where: { $0.id == entry.id }), outbox[i].phase == "stopped" {
                    entry.phase = "stopped"
                    ReplyStream.finish(&entry)
                    try? checkpoint()
                    project(entry)
                }
            }
            catch {
                if ["queued", "preparing"].contains(entry.phase) { entry.phase = "failed" }
                else if entry.phase != "failed" { entry.phase = "unknown" }
                entry.error = error.localizedDescription
                try? checkpoint()
                project(entry)
                // An uncertain result is a recoverable queue row, not a
                // permanent global error banner. Town Client keeps that
                // status on the message and lets history reconciliation clear
                // it; only a retryable preparation failure needs the banner.
                // Keep delivery errors on the originating bubble. Town Client
                // does not replace the conversation with a queue banner.
                if notice == "发送未完成，请查看发送队列。" { notice = nil }
            }
        }
    }
    func project(_ entry: PendingSend) {
        guard let i = conversations.firstIndex(where: { $0.id == entry.sceneID && $0.endpoint == entry.endpoint }) else { return }
        var room = conversations[i]
        var changed = false
        let rows = [
            Message(id: entry.userID, role: "user", text: entry.preparedText ?? entry.text,
                    sceneID: entry.sceneID, timestamp: entry.createdAt, files: entry.files, process: entry.process,
                    localBaseline: entry.baseline, localAfter: entry.afterID)
        ] + ReplyStream.messages(entry)
        for message in rows {
            if let j = room.messages.firstIndex(where: { $0.id == message.id }) {
                // Preserve server-confirmed rows and publish only changed content.
                if room.messages[j].sequence == nil || room.messages[j].sequence == message.sequence || room.messages[j].streaming == true {
                    var updated = message
                    updated.sequence = message.sequence ?? room.messages[j].sequence
                    updated.persistedText = room.messages[j].persistedText
                    // A text-matched history echo can be an early snapshot.
                    // Only explicit stream persistence metadata makes it final.
                    if message.sequence == nil, message.text != room.messages[j].text {
                        updated.persistedText = nil
                    }
                    if updated.streaming == false, let authoritative = updated.persistedText { updated.text = authoritative }
                    if room.messages[j] != updated { room.messages[j] = updated; changed = true }
                } else if message.role == "user", room.messages[j].process != message.process {
                    // History can acknowledge the user while its run is still
                    // active. Keep the authoritative user text/sequence, but
                    // continue publishing its locally received process.
                    room.messages[j].process = message.process
                    changed = true
                }
            } else { room.messages.append(message); changed = true }
            if let sequence = message.sequence,
               let duplicate = room.messages.firstIndex(where: { $0.sequence == sequence && $0.id != message.id }),
               let live = room.messages.firstIndex(where: { $0.id == message.id }) {
                var confirmed = room.messages[duplicate]
                confirmed.id = message.id
                confirmed.replyTo = message.replyTo
                confirmed.process = message.process
                confirmed.streaming = message.streaming
                if message.streaming == true {
                    confirmed.persistedText = confirmed.text
                    confirmed.text = message.text
                }
                room.messages[live] = confirmed
                room.messages.remove(at: duplicate)
                changed = true
            }
        }
        if changed { room.updated = Date(); conversations[i] = room }
        if busy, activeScene == entry.sceneID, ["sending", "waiting"].contains(entry.phase),
           let latest = rows.last, latest.role == "being", !latest.text.isEmpty,
           streamingReplyID != latest.id { streamingReplyID = latest.id }
    }
    private func updateActivity(_ value: String) {
        if activity != value { activity = value }
    }
    func consume(_ type: String, _ value: [String: Any], entry: inout PendingSend) throws {
        if value["scene_id"] is NSNull { sbsActivity = ["message_stop","done","end"].contains(type) ? "" : "正在自主活动"; return }
        if let scene = value["scene_id"] as? String, scene != entry.sceneID { return }
        if let id = value["stream_id"] as? String { entry.streamID = id; streamID = id }
        ReplyStream.consume(type, value, entry: &entry)
        switch type {
        case "content_block_delta":
            if let delta = value["delta"] as? [String: Any] {
                if let text = delta["text"] as? String, !text.isEmpty { updateActivity("正在回复") }
                else if let thinking = delta["thinking"] as? String, !thinking.isEmpty {
                    updateActivity("思考中"); entry.process += thinking
                }
            }
        case "text", "message": if let text = (value["text"] ?? value["content"]) as? String { if !text.isEmpty { updateActivity("正在回复") } }
        case "thinking", "reasoning": updateActivity("思考中"); entry.process += ReplyStream.reasoningText(value)
        case "tool_use": updateActivity("正在使用 \(value["name"] as? String ?? "工具")"); entry.process += "\n\(activity)\n" + String(describing: value["input"] ?? "")
        case "tool_result": entry.process += "\n" + String(describing: value["content"] ?? value["result"] ?? ""); updateActivity("思考中")
        case "message_stop": if !ReplyStream.hasFinalReply(entry) { updateActivity("等待最终回复") }
        case "error": throw PortalError.server("Being 返回错误")
        default: break
        }
        if entry.process.count > 64000 {
            entry.process = String(entry.process.suffix(64000))
        }
    }
    func recover(_ entry: inout PendingSend, connection c: Connection) async throws -> Bool {
        activity = "正在恢复回复"
        var idleSince = Date()
        var attempts = 0
        var failures = 0
        while Date().timeIntervalSince(idleSince) < 300 {
            try Task.checkCancellation()
            do {
                let (bytes, response) = try await session.data(for: request(c, "/api/stream/active?after=\(entry.cursor)"))
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 204 { return try await reconcile(&entry, connection: c) }
                guard code == 200, let data = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw PortalError.http(code) }
                let id = data["stream_id"] as? String
                if let expected = entry.streamID, id != expected { return try await reconcile(&entry, connection: c) }
                // A 202 may be queued behind an unrelated scene; never consume that scene's stream.
                if entry.streamID == nil, data["scene_id"] as? String != entry.sceneID { if try await reconcile(&entry, connection: c) { return true } }
                else {
                    entry.streamID = id; streamID = id
                    let events = data["events"] as? [[String: Any]] ?? []
                    if let first = events.first?["seq"] as? Int, first > entry.cursor + 1 { return try await reconcile(&entry, connection: c) }
                    for event in events {
                        guard let seq = event["seq"] as? Int, seq > entry.cursor else { continue }
                        let type = event["event"] as? String ?? ""
                        let value = event["data"] as? [String: Any] ?? [:]
                        if ReplyStream.isProgress(type, value, scene: entry.sceneID) { idleSince = Date() }
                        try consume(type, value, entry: &entry); entry.cursor = seq
                    }
                    project(entry)
                    if let i = outbox.firstIndex(where: { $0.id == entry.id }) { outbox[i] = entry; try saveOutbox() }
                    if data["finished"] as? Bool == true { return try await reconcile(&entry, connection: c) }
                }
                failures = 0
            } catch is CancellationError { throw CancellationError() }
            catch { failures += 1; if failures >= 5 { throw error } }
            attempts += 1
            try await Task.sleep(for: .seconds(min(5, 1 + attempts / 3)))
        }
        return false
    }
    func historyBaseline(_ c: Connection, after: Int) async throws -> Int {
        var cursor = after
        while true {
            let data = try await json(c, "/api/history?limit=500&after=\(cursor)")
            let next = (data["messages"] as? [[String: Any]] ?? []).compactMap { $0["seq"] as? Int }.max() ?? cursor
            if next <= cursor { return cursor }; cursor = next
        }
    }
    func reconcile(_ entry: inout PendingSend, connection c: Connection) async throws -> Bool {
        var cursor = entry.baseline
        var sawUser = false
        var reply = ""
        var confirmed: [Message] = []
        var ended = false
        while !ended {
            let result = try await json(c, "/api/history?limit=500&after=\(cursor)")
            let rows = (result["messages"] as? [[String: Any]] ?? []).filter { ($0["seq"] as? Int ?? 0) > cursor }.sorted { ($0["seq"] as? Int ?? 0) < ($1["seq"] as? Int ?? 0) }
            if rows.isEmpty { break }
            for row in rows where row["scene_id"] as? String == entry.sceneID {
                let text = HistoryRules.text(row["content"])
                if row["role"] as? String == "user" {
                    if sawUser { ended = true; break }
                    sawUser = DeliveryRules.matchesSubmittedText(text, entry.preparedText ?? entry.text)
                    if sawUser { confirmed.append(Message(id: entry.userID, role: "user", text: SceneRules.stripTransition(text), sceneID: entry.sceneID, sequence: row["seq"] as? Int, timestamp: row["at"] as? String, files: entry.files)) }
                } else if sawUser, row["type"] as? String != "marker", row["from"] as? String != "system" { reply += (reply.isEmpty ? "" : "\n\n") + text; confirmed.append(Message(role: "being", text: text, sceneID: entry.sceneID, sequence: row["seq"] as? Int, timestamp: row["at"] as? String)) }
            }
            cursor = rows.compactMap { $0["seq"] as? Int }.max() ?? cursor
        }
        guard sawUser, !reply.isEmpty else { return false }
        entry.reply = reply
        if let i = conversations.firstIndex(where: { $0.id == entry.sceneID && $0.endpoint == entry.endpoint }) {
            confirmed = ReplyStream.bindHistory(confirmed, to: entry)
            let replaced = Set(confirmed.map(\.id))
            let sequences = Set(confirmed.compactMap(\.sequence))
            let remaining = conversations[i].messages.filter {
                !replaced.contains($0.id) && !($0.sequence.map(sequences.contains) ?? false)
            }
            conversations[i].messages = HistoryRules.merge(remaining, confirmed)
        }
        return true
    }
}

extension Store {
    func interruptQueued(_ id: String) async {
        guard busy, let currentScene = activeScene, let c = connection, streamID != nil,
              let target = outbox.first(where: { $0.id == id && $0.phase == "queued" && $0.endpoint == c.endpoint && $0.sceneID == currentScene }) else { return }
        // Save priority before stop: the worker drains immediately on exit.
        // Reordering afterwards races that drain and can send an older item first.
        let old = outbox
        outbox.removeAll { $0.id == target.id }
        outbox.insert(target, at: 0)
        do { try saveOutbox() }
        catch { outbox = old; notice = "优先发送未能保存，请重试。"; return }
        await stop()
    }
}
