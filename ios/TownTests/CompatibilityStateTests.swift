import Combine
import XCTest
@testable import Town

@MainActor final class CompatibilityStateTests: XCTestCase {
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
        let observation = store.$draft.dropFirst().sink { drafts.append($0) }
        store.draft = "retained draft"
        XCTAssertEqual(drafts, ["retained draft"])
        withExtendedLifetime(observation) {}
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
