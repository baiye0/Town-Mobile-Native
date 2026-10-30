import Combine
import XCTest
@testable import Town

@MainActor final class CompatibilityStateTests: XCTestCase {
    func testUnreadableConversationIsNotReplacedByEmptyHistory() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let original = Data("[{\"id\":\"recoverable-fragment\"".utf8)
        try original.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = Store(conversationFile: file)
        XCTAssertTrue(store.conversationStorageUnavailable)
        XCTAssertFalse(store.persist())
        store.draft = "unsent draft"
        store.send()
        XCTAssertEqual(store.draft, "unsent draft")
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testProcessIsVisibleBeforeTextAndStaysOnTheInitiatingTurn() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/progress?token=test")
        store.connection = connection
        store.selected = "s"
        store.showAllScenes = true
        store.timeline = []
        store.conversations = [Conversation(id: "s", endpoint: connection.endpoint)]
        var entry = PendingSend(endpoint: connection.endpoint, sceneID: "s", title: "s", text: "question")
        try store.consume("reasoning", ["delta": "检查上下文"], entry: &entry)
        store.project(entry)
        XCTAssertEqual(store.displayMessages.count, 1)
        XCTAssertEqual(store.displayMessages[0].process, "检查上下文")
        // A refresh has already acknowledged the initiating user message.
        store.conversations[0].messages[0].sequence = 11
        try store.consume("content_block_delta", ["delta": ["type": "thinking_delta", "thinking": "，检查细节"]], entry: &entry)
        try store.consume("content_block_delta", ["delta": ["type": "provider_text", "text": "逐步"]], entry: &entry)
        store.project(entry)
        XCTAssertEqual(store.displayMessages.last?.text, "逐步")
        XCTAssertEqual(store.displayMessages.first?.process, "检查上下文，检查细节")
        XCTAssertEqual(store.displayMessages.first?.sequence, 11)
        XCTAssertNil(store.displayMessages.last?.process)
        try store.consume("content_block_delta", ["delta": ["text": "显示"]], entry: &entry)
        store.project(entry)
        XCTAssertEqual(store.displayMessages.last?.text, "逐步显示")
        try store.consume("reasoning", ["scene_id": "other", "text": "其他场景"], entry: &entry)
        XCTAssertFalse(entry.process.contains("其他场景"))
    }

    func testNestedMessageMutationPublishesAndInvalidatesDisplayCache() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/compat?token=test")
        store.connection = connection
        store.showAllScenes = false
        store.selected = "test-scene"
        store.conversations = [Conversation(id: "test-scene", endpoint: connection.endpoint,
                                            messages: [Message(role: "being", text: "first")])]
        XCTAssertEqual(store.displayMessages.first?.text, "first")
        var updates = 0
        let observation = store.objectWillChange.sink { updates += 1 }
        store.conversations[0].messages[0].text = "streamed reply"
        XCTAssertGreaterThan(updates, 0)
        XCTAssertEqual(store.displayMessages.first?.text, "streamed reply")
        withExtendedLifetime(observation) {}
    }

    func testSelectingSceneRefreshesComputedMessagesAndDraftPublishes() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/compat?token=test")
        store.connection = connection
        store.showAllScenes = false
        store.conversations = [
            Conversation(id: "one", endpoint: connection.endpoint, messages: [Message(role: "user", text: "one")]),
            Conversation(id: "two", endpoint: connection.endpoint, messages: [Message(role: "user", text: "two")])
        ]
        store.selected = "one"
        XCTAssertEqual(store.displayMessages.first?.text, "one")
        store.selected = "two"
        XCTAssertEqual(store.displayMessages.first?.text, "two")
        var drafts: [String] = []
        let observation = store.composer.$draft.dropFirst().sink { drafts.append($0) }
        store.draft = "retained draft"
        XCTAssertEqual(drafts, ["retained draft"])
        withExtendedLifetime(observation) {}
    }

    func testTypingPublishesOnlyComposerChanges() {
        let store = Store()
        var storeUpdates = 0
        var drafts: [String] = []
        let storeObservation = store.objectWillChange.sink { storeUpdates += 1 }
        let draftObservation = store.composer.$draft.dropFirst().sink { drafts.append($0) }
        for value in ["n", "ni", "你", "你好"] { store.draft = value }
        XCTAssertEqual(storeUpdates, 0)
        XCTAssertEqual(drafts, ["n", "ni", "你", "你好"])
        withExtendedLifetime((storeObservation, draftObservation)) {}
    }
    func testHistoryHydrationPublishesOnceAcrossManyScenesAndSkipsUnchangedRefresh() throws {
        let store = Store()
        let endpoint = "https://example.invalid/history-batch"
        store.conversations = []
        store.timeline = (0..<1000).map { Message(role: "being", text: "message \($0)", sceneID: "scene-\($0 % 100)", sequence: $0 + 1) }
        var updates = 0
        let observation = store.objectWillChange.sink { updates += 1 }
        store.hydrateHistory(endpoint)
        XCTAssertEqual(store.conversations.count, 100)
        XCTAssertEqual(store.conversations.flatMap(\.messages).count, 1000)
        XCTAssertEqual(updates, 1)
        store.hydrateHistory(endpoint)
        XCTAssertEqual(updates, 1, "An unchanged refresh must not invalidate all history rows")
        withExtendedLifetime(observation) {}
    }

    func testBurstPresentationKeepsFirstAndLatestWithoutLatePublish() async throws {
        var snapshots: [String] = []
        let frames = StreamPresentation { snapshots.append($0.reply) }
        var entry = PendingSend(endpoint: "https://example.invalid", sceneID: "s", title: "s", text: "prompt")
        entry.reply = "first"; frames.submit(entry)
        XCTAssertEqual(snapshots, ["first"])
        for _ in 0..<2000 { entry.reply += "x"; frames.submit(entry) }
        XCTAssertEqual(snapshots.count, 1)
        frames.flush()
        XCTAssertEqual(snapshots.last, entry.reply); XCTAssertEqual(snapshots.count, 2)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(snapshots.count, 2)
    }

    func testLongHistoryStreamingProjectionPerformance() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/performance?token=test")
        store.connection = connection; store.selected = "s"; store.showAllScenes = true
        let history = (1...1000).map { (index: Int) in Message(role: "being", text: "Historical message \(index)", sceneID: "s", sequence: index) }
        store.timeline = history
        store.conversations = [Conversation(id: "s", endpoint: connection.endpoint, messages: history)]
        var entry = PendingSend(endpoint: connection.endpoint, sceneID: "s", title: "s", text: "prompt", baseline: 1000)
        entry.phase = "sending"
        ReplyStream.consume("text", ["text": "first"], entry: &entry); store.project(entry)
        XCTAssertEqual(store.displayMessages.count, 1002)
        let clock = ContinuousClock(); let start = clock.now
        for _ in 0..<100 {
            ReplyStream.consume("text", ["text": " next"], entry: &entry); store.project(entry)
            XCTAssertEqual(store.displayMessages.last?.text, entry.reply)
        }
        print("STREAM_PERFORMANCE: 100 content updates with 1000 history rows: \(start.duration(to: clock.now))")
        XCTAssertEqual(store.displayMessages.count, 1002)
        XCTAssertEqual(store.displayMessages.last?.id, entry.replyID)
    }

    func testThinkingUpdatesDoNotPublishTheConversationList() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/thinking?token=test")
        store.connection = connection; store.selected = "s"; store.showAllScenes = true
        let history = (1...1000).map { (index: Int) in Message(role: "being", text: "History \(index)", sceneID: "s", sequence: index) }
        store.timeline = history
        store.conversations = [Conversation(id: "s", endpoint: connection.endpoint, messages: history)]
        var entry = PendingSend(endpoint: connection.endpoint, sceneID: "s", title: "s", text: "prompt", baseline: 1000)
        entry.phase = "sending"
        store.project(entry, live: true)
        XCTAssertEqual(store.displayMessages.count, 1001)
        var listUpdates = 0
        let observation = store.objectWillChange.sink { listUpdates += 1 }
        let clock = ContinuousClock(); let start = clock.now
        for _ in 0..<2000 {
            try store.consume("reasoning", ["delta": "核对上下文。"], entry: &entry)
            store.project(entry, live: true)
        }
        print("THINKING_PERFORMANCE: 2000 events with 1000 history rows: \(start.duration(to: clock.now)); list publications: \(listUpdates)")
        XCTAssertEqual(listUpdates, 0)
        XCTAssertEqual(store.runProgress.process, String(repeating: "核对上下文。", count: 2000))
        XCTAssertEqual(store.displayMessages.count, 1001)
        store.project(entry)
        XCTAssertEqual(store.displayMessages.last?.process, entry.process)
        withExtendedLifetime(observation) {}
    }

    func testWhitespacePrefixBecomesVisibleBeforeStreamCompletion() throws {
        for allScenes in [false, true] {
            for prefix in ["\n", "   ", "\t\r\n"] {
                let store = Store()
                let connection = try Connection("https://example.invalid/whitespace-stream?token=test")
                store.connection = connection; store.selected = "s"
                store.showAllScenes = allScenes; store.timeline = []
                store.conversations = [Conversation(id: "s", endpoint: connection.endpoint)]
                store.busy = true; store.activeScene = "s"
                var entry = PendingSend(endpoint: connection.endpoint, sceneID: "s", title: "s", text: "prompt")
                entry.phase = "sending"
                ReplyStream.consume("text", ["text": prefix], entry: &entry)
                store.project(entry, live: true)
                XCTAssertFalse(store.displayMessages.contains { $0.id == entry.replyID })

                var listUpdates = 0
                let observation = store.objectWillChange.sink { listUpdates += 1 }
                ReplyStream.consume("text", ["text": "Hello"], entry: &entry)
                store.project(entry, live: true)
                let visible = try XCTUnwrap(store.displayMessages.first { $0.id == entry.replyID })
                XCTAssertEqual(visible.text, prefix + "Hello")
                XCTAssertEqual(visible.streaming, true)
                XCTAssertEqual(listUpdates, 1, "The first visible text must insert the previously hidden row")

                let row = store.liveReply(for: visible)
                ReplyStream.consume("text", ["text": " world"], entry: &entry)
                store.project(entry, live: true)
                XCTAssertEqual(listUpdates, 1, "Subsequent tokens must keep using row-only updates")
                XCTAssertEqual(row.message.text, prefix + "Hello world")
                XCTAssertEqual(store.displayMessages.first { $0.id == entry.replyID }?.text, row.message.text)
                withExtendedLifetime(observation) {}
            }
        }
    }

    func testLiveReplyAndCheckpointsPublishOnlyTheirOwnRow() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/isolated?token=test")
        store.connection = connection; store.selected = "s"; store.showAllScenes = true
        let history = (1...1000).map { (index: Int) in Message(role: "being", text: "History \(index)", sceneID: "s", sequence: index) }
        store.timeline = history
        store.conversations = [Conversation(id: "s", endpoint: connection.endpoint, messages: history)]
        var entry = PendingSend(endpoint: connection.endpoint, sceneID: "s", title: "s", text: "prompt", baseline: 1000)
        entry.phase = "sending"; store.outbox = [entry]
        ReplyStream.consume("text", ["text": "first"], entry: &entry); store.project(entry, live: true)
        let row = store.liveReply(for: try XCTUnwrap(store.displayMessages.last))
        var listUpdates = 0, rowUpdates = 0
        let listObservation = store.objectWillChange.sink { listUpdates += 1 }
        let rowObservation = row.objectWillChange.sink { rowUpdates += 1 }
        for index in 1...100 {
            try store.consume("text", ["text": " next"], entry: &entry)
            entry.cursor = index
            store.project(entry, live: true)
            try store.updateCheckpoint(entry)
        }
        XCTAssertEqual(listUpdates, 0, "Text and periodic recovery checkpoints must not rebuild history")
        XCTAssertEqual(rowUpdates, 100)
        XCTAssertEqual(row.message.text, entry.reply)
        XCTAssertEqual(store.displayMessages.last?.text, entry.reply)
        XCTAssertEqual(store.conversations[0].messages.last?.text, entry.reply)
        XCTAssertEqual(store.outbox.first?.cursor, 100)
        ReplyStream.finish(&entry); store.project(entry)
        XCTAssertGreaterThan(listUpdates, 0, "Finalization must refresh static history")
        XCTAssertEqual(row.message.streaming, false)
        XCTAssertEqual(store.displayMessages.count, 1002)
        withExtendedLifetime((listObservation, rowObservation)) {}
    }

    func testMixedProgressCannotDiscardPendingTextFrame() {
        var replies: [String] = [], processes: [String] = []
        let frames = StreamPresentation(publish: { replies.append($0.reply) }, publishProgress: { processes.append($0.process) })
        var entry = PendingSend(endpoint: "test", sceneID: "s", title: "s", text: "prompt")
        entry.process = "thinking"; frames.submit(entry, progressOnly: true)
        entry.reply = "visible"; frames.submit(entry)
        entry.process += " more"; frames.submit(entry, progressOnly: true)
        frames.flush()
        XCTAssertEqual(replies, ["visible"])
        XCTAssertEqual(processes, ["thinking"])
    }

    func testRepeatedBackgroundThinkingDoesNotRebuildChat() throws {
        let store = Store()
        var entry = PendingSend(endpoint: "test", sceneID: "s", title: "s", text: "prompt")
        try store.consume("reasoning", ["scene_id": NSNull(), "delta": "background"], entry: &entry)
        var updates = 0
        let observation = store.objectWillChange.sink { updates += 1 }
        for _ in 0..<1000 {
            try store.consume("reasoning", ["scene_id": NSNull(), "delta": "background"], entry: &entry)
        }
        XCTAssertEqual(updates, 0)
        XCTAssertTrue(entry.process.isEmpty)
        try store.consume("done", ["scene_id": NSNull()], entry: &entry)
        XCTAssertEqual(store.sbsActivity, "")
        XCTAssertEqual(updates, 1)
        withExtendedLifetime(observation) {}
    }

    func testThinkingCheckpointsDoNotInvalidateHistory() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/checkpoint?token=test")
        store.connection = connection; store.selected = "s"
        store.conversations = [Conversation(id: "s", endpoint: connection.endpoint)]
        var entry = PendingSend(endpoint: connection.endpoint, sceneID: "s", title: "s", text: "prompt")
        entry.phase = "sending"; store.outbox = [entry]; store.project(entry)
        var updates = 0
        let observation = store.objectWillChange.sink { updates += 1 }
        for index in 1...2000 {
            try store.consume("reasoning", ["delta": "核对上下文。"], entry: &entry)
            store.runProgress.process = entry.process
            if index % 50 == 0 { entry.cursor = index; try store.updateCheckpoint(entry) }
        }
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(store.outbox.first?.process, entry.process)
        entry.phase = "unknown"; entry.error = "test"; try store.updateCheckpoint(entry)
        XCTAssertGreaterThan(updates, 0, "Actionable errors must still refresh retry controls")
        withExtendedLifetime(observation) {}
    }

    func testLongProcessChunksPreserveUnicodeAndCompleteText() async {
        let process = String(repeating: "分析 👨‍👩‍👧‍👦：上下文与工具结果。\n", count: 4000)
        let chunks = await ProcessTextParser.shared.chunks(process)
        XCTAssertEqual(chunks.joined(), process)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 1200 })
        XCTAssertGreaterThan(chunks.count, 20)
    }

    func testBackgroundMarkdownUsesReferenceDefinitionsAndFinalSource() async {
        let source = "![image][ref]\n\n```swift\nlet answer = 42\n```"
        let first = await MarkdownBlockParser.shared.parse(.init(text: source, references: "[ref]: https://example.com/first.png"))
        let second = await MarkdownBlockParser.shared.parse(.init(text: source, references: "[ref]: https://example.com/second.png"))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second, MarkdownBlocks.parse(source, imageReferences: "[ref]: https://example.com/second.png"))
        let final = await MarkdownBlockParser.shared.parse(.init(text: source + "\n\nfinal", references: ""))
        XCTAssertEqual(final.last?.text, "final")
    }

    func testClosingReplyCannotRestoreAnOlderHistoryPrefix() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/short-history?token=test")
        store.connection = connection
        store.conversations = [Conversation(id: "s", endpoint: connection.endpoint)]
        var entry = PendingSend(endpoint: connection.endpoint, sceneID: "s", title: "s", text: "prompt")
        entry.streamID = "stream"
        ReplyStream.consume("text", ["text": "first and final"], entry: &entry)
        ReplyStream.consume("meta", ["persisted": ["kind": "self", "from": "final", "seq": 12, "stream_id": "stream"]], entry: &entry)
        store.project(entry)
        store.conversations[0].messages = HistoryRules.merge(store.conversations[0].messages,
            [Message(role: "being", text: "first", sceneID: "s", sequence: 12)])
        ReplyStream.finish(&entry)
        store.project(entry)
        XCTAssertEqual(store.conversations[0].messages.last?.text, "first and final")
    }

    func testChatTimeFormattingPreservesTodayOlderAndInvalidTimestamps() {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        let display = DateFormatter(); display.timeStyle = .short
        let now = Date()
        var sources = (0..<1000).map { iso.string(from: now.addingTimeInterval(-Double($0) * 3600)) }
        sources += [standard.string(from: now), "invalid-T-timestamp"]
        let referenceStart = Date()
        let expected = sources.map { value -> String in
            guard let date = iso.date(from: value) ?? standard.date(from: value) else {
                return String(value.replacingOccurrences(of: "T", with: " ").prefix(16))
            }
            display.dateStyle = Calendar.current.isDateInToday(date) ? .none : .medium
            return display.string(from: date)
        }
        let referenceMS = Date().timeIntervalSince(referenceStart) * 1000
        XCTAssertEqual(sources.map(chatTime), expected)
        let cachedStart = Date()
        XCTAssertEqual(sources.map(chatTime), expected)
        let cachedMS = Date().timeIntervalSince(cachedStart) * 1000
        print("Chat timestamp benchmark (1002 rows): previous=\(referenceMS)ms cached=\(cachedMS)ms")
    }

    func testProgressPresentationEventuallyPublishesTheLastPacket() async throws {
        var snapshots: [String] = []
        let trailing = expectation(description: "Trailing progress is published without another packet")
        let frames = StreamPresentation {
            snapshots.append($0.process)
            if $0.process == "last" { trailing.fulfill() }
        }
        var entry = PendingSend(endpoint: "https://example.invalid", sceneID: "s", title: "s", text: "prompt")
        entry.process = "first"; frames.submit(entry, progressOnly: true)
        entry.process = "last"; frames.submit(entry, progressOnly: true)
        XCTAssertEqual(snapshots, ["first"])
        await fulfillment(of: [trailing], timeout: 2)
        XCTAssertEqual(snapshots, ["first", "last"])
        frames.flush()
        XCTAssertEqual(snapshots.count, 2)
    }

    func testHistoryAcknowledgementDoesNotFreezeAnActiveReply() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/live?token=test")
        store.connection = connection
        var entry = PendingSend(endpoint: connection.endpoint, sceneID: "s", title: "s", text: "question")
        entry.phase = "sending"
        store.conversations = [Conversation(id: "s", endpoint: connection.endpoint)]
        ReplyStream.consume("text", ["text": "first"], entry: &entry)
        store.project(entry)
        let remote = Message(role: "being", text: "first", sceneID: "s", sequence: 12)
        store.conversations[0].messages = HistoryRules.merge(store.conversations[0].messages, [remote])
        ReplyStream.consume("text", ["text": " second"], entry: &entry)
        store.project(entry)
        let reply = try XCTUnwrap(store.conversations[0].messages.first { $0.id == entry.replyID })
        XCTAssertEqual(reply.sequence, 12)
        XCTAssertEqual(reply.text, "first second")
        XCTAssertEqual(store.conversations[0].messages.filter { $0.role == "being" }.count, 1)
        ReplyStream.finish(&entry)
        store.project(entry)
        XCTAssertEqual(store.conversations[0].messages.first { $0.id == entry.replyID }?.text, "first second")
    }

    func testSocialUnreadDictionaryMutationPublishes() {
        let social = SocialStore()
        var counts: [Int] = []
        let observation = social.$counts.dropFirst().sink { counts.append($0["mail"] ?? 0) }
        social.counts["mail", default: 0] += 1
        social.acknowledge(.mail)
        XCTAssertEqual(counts, [1, 0])
        XCTAssertEqual(social.unread(.mail), 0)
        withExtendedLifetime(observation) {}
    }

    func testFiresideUnreadIsScopedToRoomAndLoadedMessages() {
        let social = SocialStore()
        social.identity = TownIdentity(token: "test", id: "t_me", name: "Me")
        for room in ["1", "2"] {
            for seq in [1, 2] {
                social.receive(eventType: "fireside", object: ["fireside_id": room, "seq": seq, "town_id": "t_peer"])
            }
        }
        XCTAssertEqual(social.unread(.firesides), 4)
        XCTAssertEqual(social.unread(firesideID: "1"), 2)
        social.acknowledge(.firesides)
        social.acknowledge(firesideID: "", messages: [])
        XCTAssertEqual(social.unread(.firesides), 4, "Opening the directory must retain all unread badges")
        social.acknowledge(firesideID: "1", messages: [["seq": 1]])
        XCTAssertEqual(social.unread(firesideID: "1"), 1)
        XCTAssertEqual(social.unread(firesideID: "2"), 2)
        XCTAssertEqual(social.unread(.firesides), 3)
        social.acknowledge(firesideID: "1", messages: [["seq": 1], ["seq": 2]])
        XCTAssertEqual(social.unread(.firesides), 2)
        XCTAssertEqual(social.unread(firesideID: "1"), 0)
    }

    func testFiresideUnreadDeduplicatesReplayAndIgnoresOwnMessages() {
        let social = SocialStore()
        social.identity = TownIdentity(token: "test", id: "t_me", name: "Me")
        let event: [String: Any] = ["fireside_id": 1, "id": "one", "sender_town_id": "t_peer"]
        XCTAssertEqual(social.receive(eventType: "fireside", object: event), "firesides")
        XCTAssertNil(social.receive(eventType: "fireside", object: event))
        XCTAssertNil(social.receive(eventType: "fireside", object: ["fireside_id": 1, "id": "own", "sender_town_id": "t_me"]))
        XCTAssertEqual(social.unread(firesideID: "1"), 1)
        social.acknowledge(firesideID: "1", messages: [["id": "one"]])
        social.receive(eventType: "fireside", object: event)
        XCTAssertEqual(social.unread(.firesides), 0, "Replay must not restore a read badge")
        social.resetUnread()
        XCTAssertTrue(social.firesideUnread.isEmpty)
        XCTAssertEqual(social.unread(.firesides), 0)
        social.receive(eventType: "fireside", object: event)
        XCTAssertEqual(social.unread(.firesides), 1, "Identity reset also resets event deduplication")
    }

    func testFiresideUnreadRetainsMessagesArrivingDuringLoad() {
        let social = SocialStore()
        social.identity = TownIdentity(token: "test", id: "t_me", name: "Me")
        social.receive(eventType: "fireside", object: ["fireside_id": "a", "seq": 1, "town_id": "t_peer"])
        let response: [[String: Any]] = [["seq": 1]]
        social.receive(eventType: "fireside", object: ["fireside_id": "a", "seq": 2, "town_id": "t_peer"])
        social.acknowledge(firesideID: "a", messages: response)
        XCTAssertEqual(social.unread(firesideID: "a"), 1)
        social.acknowledge(firesideID: "a", messages: [])
        XCTAssertEqual(social.unread(.firesides), 1, "Empty or failed loads must not clear pending messages")
    }

    func testNavigationTabsPersistAndSelectionPublishes() {
        let saved = UserDefaults.standard.object(forKey: "navigation.tabs")
        defer { UserDefaults.standard.set(saved, forKey: "navigation.tabs") }
        let nav = NavigationState()
        var selection: [String] = []
        let observation = nav.$selected.dropFirst().sink { selection.append($0) }
        nav.selected = "more"
        nav.tabs = [.chat, .mail]
        XCTAssertEqual(selection, ["more"])
        XCTAssertEqual(NavigationState().tabs, [.chat, .mail])
        withExtendedLifetime(observation) {}
    }

    func testHistoryBackForwardAndNewBranch() {
        let history = PageHistory()
        let first = UUID(), second = UUID(), replacement = UUID()
        history.navigate([first, second])
        history.back()
        XCTAssertEqual(history.path, [first])
        XCTAssertEqual(history.forward, [second])
        history.advance()
        XCTAssertEqual(history.path, [first, second])
        history.back()
        history.navigate([first, replacement])
        XCTAssertTrue(history.forward.isEmpty)
    }

    func testUpdateMessagePublishesWithoutNetwork() {
        let update = AppUpdateStore()
        var messages: [String] = []
        let observation = update.$message.dropFirst().sink { messages.append($0) }
        update.message = "test status"
        XCTAssertEqual(messages, ["test status"])
        withExtendedLifetime(observation) {}
    }

    func testSpeechStopPublishesAndClearsVisibleState() {
        let speech = SpeechInput()
        var active: [Bool] = []
        let observation = speech.$active.dropFirst().sink { active.append($0) }
        speech.stop()
        XCTAssertEqual(active, [false])
        XCTAssertNil(speech.startedAt)
        XCTAssertFalse(speech.finishing)
        XCTAssertEqual(speech.levels.count, 36)
        withExtendedLifetime(observation) {}
    }
}

@MainActor final class IntelligentUIStateTests: XCTestCase {
    func testSceneSwitchPreservesExplicitUIModeIndependentlyOfSelection() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/ui-mode?token=test")
        store.connection = connection
        store.conversations = [Conversation(id: "one", endpoint: connection.endpoint), Conversation(id: "two", endpoint: connection.endpoint)]
        store.sceneDirectory[connection.endpoint] = ["one", "two"]
        store.selected = "one"
        // A newly enabled UI request does not have a prior surface selection.
        store.intelligentUI = true
        store.selectScene("two")
        XCTAssertFalse(store.intelligentUI)
        store.selectScene("one")
        XCTAssertTrue(store.intelligentUI)
        XCTAssertNil(store.intelligentUISelection)
        // Disabling the feature must survive a round trip even with a selection.
        store.intelligentUISelection = "{\"revision\":1}"
        store.intelligentUI = false
        store.selectScene("two")
        store.selectScene("one")
        XCTAssertFalse(store.intelligentUI)
        XCTAssertEqual(store.intelligentUISelection, "{\"revision\":1}")
        store.selectScene("one")
        XCTAssertFalse(store.intelligentUI)
    }

    func testUIStatePersistsNullAndIsolatesScopes() throws {
        let suite = "IntelligentUIStateTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        IntelligentUIStateCache.save(["optional": NSNull(), "count": 3], key: "surface", scope: "one", defaults: defaults)
        let restored = try XCTUnwrap(IntelligentUIStateCache.load(scope: "one", defaults: defaults)["surface"] as? [String: Any])
        XCTAssertTrue(restored["optional"] is NSNull)
        XCTAssertEqual(restored["count"] as? Int, 3)
        XCTAssertTrue(IntelligentUIStateCache.load(scope: "two", defaults: defaults).isEmpty)
    }
    func testSelectionFollowsSceneAndClearDoesNotChangeDraft() throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/ui?token=test")
        store.connection = connection
        store.conversations = [Conversation(id: "one", endpoint: connection.endpoint), Conversation(id: "two", endpoint: connection.endpoint)]
        store.sceneDirectory[connection.endpoint] = ["one", "two"]
        store.selected = "one"
        store.draft = "修改人数"
        store.intelligentUI = true
        store.intelligentUISelection = "{\"revision\":1}"
        store.selectScene("two")
        XCTAssertNil(store.intelligentUISelection)
        XCTAssertFalse(store.intelligentUI)
        store.selectScene("one")
        XCTAssertEqual(store.intelligentUISelection, "{\"revision\":1}")
        XCTAssertEqual(store.draft, "修改人数")
        store.intelligentUISelection = nil
        XCTAssertEqual(store.draft, "修改人数")
    }
    func testFileExporterPreservesOriginalBytesAndType() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let original = Data([137,80,78,71,13,10,26,10,1,2,3,4])
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try ImageFileDocument(url: url)
        XCTAssertEqual(document.data, original)
        XCTAssertEqual(document.type.identifier, "public.png")
    }
}
