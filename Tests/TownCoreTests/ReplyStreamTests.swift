import Foundation
import Testing
@testable import TownCore

private func pending() -> PendingSend {
    PendingSend(endpoint: "https://example.invalid", sceneID: "s", title: "s", text: "question", baseline: 10)
}

@Test func keepaliveDoesNotDiscardFollowingReplyFrames() throws {
    let wire = ": heartbeat\n\nevent: ping\ndata: keepalive\n\nevent: content_block_delta\ndata: {\"delta\":{\"type\":\"provider_text\",\"text\":\"第一段\"}}\n\nevent: content_block_delta\ndata: {\"delta\":{\"text\":\"第二段\"}}\n\n"
    var parser = SSEByteParser()
    var entry = pending()
    var snapshots: [String] = []
    for byte in wire.utf8 {
        if let event = try parser.consume(byte), let value = event.payload {
            ReplyStream.consume(event.name, value, entry: &entry)
            snapshots.append(entry.reply)
        }
    }
    #expect(snapshots == ["第一段", "第一段第二段"])
    #expect(entry.bubbles?.first?.closed == false)
}

@Test func reasoningDoesNotBecomeReplyTextAndRunSurvivesHistoryBinding() {
    var entry = pending()
    entry.process = "先核对上下文，再检索资料"
    ReplyStream.consume("content_block_delta", ["delta": ["type": "thinking_delta", "thinking": "核对信息"]], entry: &entry)
    #expect(entry.reply.isEmpty)
    #expect(ReplyStream.reasoningText(["delta": ["thinking": "核对信息"]]) == "核对信息")
    ReplyStream.consume("text", ["text": "答复"], entry: &entry)
    let rows = [Message(id: entry.userID, role: "user", text: entry.text, sequence: 11),
                Message(role: "being", text: "答复", sequence: 12)]
    let confirmed = ReplyStream.bindHistory(rows, to: entry)
    #expect(confirmed[0].process == entry.process)
    #expect(confirmed[1].process == nil)
    #expect(ReplyStream.messages(entry).first?.process == nil)
}

@Test func toolSeparatedSpeechSharesBubbleUntilMessageStop() {
    var entry = pending()
    ReplyStream.consume("content_block_delta", ["delta": ["text": "先检查。"]], entry: &entry)
    let id = entry.bubbles!.first!.id
    ReplyStream.consume("thinking", ["text": ""], entry: &entry)
    #expect(ReplyStream.hasFinalReply(entry))
    ReplyStream.consume("tool_use", [:], entry: &entry)
    #expect(!ReplyStream.hasFinalReply(entry))
    ReplyStream.consume("text", ["text": "检查完成。"], entry: &entry)
    #expect(entry.bubbles?.count == 1)
    #expect(entry.bubbles?.first?.id == id)
    #expect(entry.reply == "先检查。\n\n检查完成。")
    ReplyStream.consume("message_stop", [:], entry: &entry)
    ReplyStream.consume("meta", ["continuation": true], entry: &entry)
    ReplyStream.consume("text", ["text": "下一条回复。"], entry: &entry)
    #expect(entry.bubbles?.count == 2)
    #expect(entry.bubbles?.last?.id != id)
    #expect(ReplyStream.messages(entry).map(\.text) == ["先检查。\n\n检查完成。", "下一条回复。"])
}

@Test func persistenceAcknowledgementsAndRestartRetainBubbleIdentity() throws {
    var entry = pending()
    entry.streamID = "stream"
    ReplyStream.consume("text", ["text": "过程"], entry: &entry)
    let metadata: [String: Any] = ["persisted": ["kind": "self", "from": "partial", "seq": 12, "stream_id": "stream"]]
    ReplyStream.consume("meta", metadata, entry: &entry)
    ReplyStream.consume("meta", metadata, entry: &entry)
    ReplyStream.consume("text", ["text": "终稿"], entry: &entry)
    ReplyStream.consume("meta", ["persisted": ["kind": "self", "from": "final", "seq": 13, "stream_id": "stream"]], entry: &entry)
    ReplyStream.consume("message_stop", [:], entry: &entry)
    let restored = try JSONDecoder().decode(PendingSend.self, from: JSONEncoder().encode(entry))
    #expect(restored.bubbles == entry.bubbles)
    #expect(restored.bubbles?.map(\.sequence) == [12, 13])
    #expect(ReplyStream.hasFinalReply(restored))
    let local = ReplyStream.messages(restored)
    let history = [Message(role: "being", text: "过程落库", sceneID: "s", sequence: 12),
                   Message(role: "being", text: "终稿落库", sceneID: "s", sequence: 13)]
    let merged = HistoryRules.merge(local, history)
    #expect(merged.map(\.id) == local.map(\.id))
    #expect(merged.map(\.text) == ["过程落库", "终稿落库"])
}

@Test func partialToolProgressIsNotACompletedReply() {
    var entry = pending()
    ReplyStream.consume("text", ["text": "正在检查"], entry: &entry)
    ReplyStream.consume("tool_use", [:], entry: &entry)
    ReplyStream.consume("message_stop", [:], entry: &entry)
    #expect(!ReplyStream.hasFinalReply(entry))
    ReplyStream.consume("content_block_delta", ["delta": ["text": ""]], entry: &entry)
    #expect(entry.bubbles?.count == 1)
    #expect(!ReplyStream.hasFinalReply(entry))
}

@Test func ordinarySendHasNoSendingBadgeButFailuresRemainActionable() {
    var entry = pending()
    for phase in ["preparing", "sending"] {
        entry.phase = phase
        #expect(DeliveryRules.bubbleStatus(entry) == nil)
    }
    for phase in ["queued", "waiting", "failed", "unknown", "stopped"] {
        entry.phase = phase
        #expect(DeliveryRules.bubbleStatus(entry) != nil)
    }
    entry.phase = "waiting"; entry.reply = "already replying"
    #expect(DeliveryRules.bubbleStatus(entry) == nil)
}

@Test func idleTimeoutOnlyResetsForProgressInTheCurrentScene() {
    #expect(ReplyStream.isProgress("tool_result", ["scene_id": "s"], scene: "s"))
    #expect(!ReplyStream.isProgress("tool_result", ["scene_id": "other"], scene: "s"))
    #expect(!ReplyStream.isProgress("text", ["text": ""], scene: "s"))
    #expect(!ReplyStream.isProgress("meta", ["stream_id": "x"], scene: "s"))
    #expect(!ReplyStream.isProgress("text", ["text": "SBS", "scene_id": NSNull()], scene: "s"))
    #expect(ReplyStream.isProgress("thinking", ["delta": ["text": "continue"]], scene: "s"))
    #expect(ReplyStream.reasoningText(["delta": "reasoning text"]) == "reasoning text")
}

@Test func historyDoesNotReplaceLiveTextUntilItsReplyEnds() {
    let live = Message(role: "being", text: "still streaming", sceneID: "s", sequence: 12, streaming: true)
    let remote = Message(role: "being", text: "canonical", sceneID: "s", sequence: 12)
    let merged = HistoryRules.merge([live], [remote])
    #expect(merged[0].id == live.id)
    #expect(merged[0].text == "still streaming")
    #expect(merged[0].persistedText == "canonical")
    var final = remote; final.streaming = false
    #expect(HistoryRules.merge(merged, [final])[0].text == "canonical")
}

@Test func finalQueueCommitCannotBeOverwrittenByAnOlderStreamCheckpoint() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }
    var entry = pending(); entry.cursor = 10; entry.reply = "first"
    OutboxCheckpoint.schedule([entry], to: url, onError: {})
    entry.cursor = 20; entry.reply = "first and second"
    try OutboxCheckpoint.save([entry], to: url)
    let restored = try JSONDecoder().decode([PendingSend].self, from: Data(contentsOf: url))
    #expect(restored[0].cursor == 20)
    #expect(restored[0].reply == "first and second")
    OutboxCheckpoint.schedule([entry], to: url, onError: {})
    try OutboxCheckpoint.save([], to: url)
    #expect(try JSONDecoder().decode([PendingSend].self, from: Data(contentsOf: url)).isEmpty)
}

@Test func identicalConfirmedRepliesKeepDistinctStreamIdentities() {
    var entry = pending()
    ReplyStream.consume("text", ["text": "same"], entry: &entry)
    ReplyStream.consume("message_stop", [:], entry: &entry)
    ReplyStream.consume("text", ["text": "same"], entry: &entry)
    let rows = [Message(role: "being", text: "same", sceneID: "s", sequence: 12),
                Message(role: "being", text: "same", sceneID: "s", sequence: 13)]
    let confirmed = ReplyStream.bindHistory(rows, to: entry)
    #expect(confirmed.map(\.id) == ReplyStream.messages(entry).map(\.id))
    #expect(Set(confirmed.map(\.id)).count == 2)
}
