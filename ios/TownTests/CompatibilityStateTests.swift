import Combine
import XCTest
@testable import Town

@MainActor final class CompatibilityStateTests: XCTestCase {
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
        let history = (1...1000).map { Message(role: "being", text: "Historical message \($0)", sceneID: "s", sequence: $0) }
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
