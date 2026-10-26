import Foundation
import Testing
@testable import TownCore

@Test func historyAheadOfStreamKeepsOneBubbleAndItsReceivedText() {
    let prompt = Message(role: "user", text: "question", sceneID: "s", sequence: 11)
    let live = Message(role: "being", text: "first", sceneID: "s", localBaseline: 10, replyTo: prompt.id, localAfter: prompt.id, streaming: true)
    let remote = Message(role: "being", text: "first second final", sceneID: "s", sequence: 12)
    let merged = HistoryRules.merge([prompt, live], [prompt, remote])
    let replies = merged.filter { $0.role == "being" }
    #expect(replies.count == 1)
    #expect(replies.first?.id == live.id)
    #expect(replies.first?.text == "first")
    #expect(replies.first?.sequence == 12)
    #expect(replies.first?.persistedText == remote.text)
    #expect(HistoryRules.merge(merged, [prompt, remote]).filter { $0.role == "being" }.count == 1)
    // The full history row may already be in the local cache before the first token.
    #expect(HistoryRules.merge([prompt, remote, live], [remote]).filter { $0.role == "being" }.count == 1)
}

@Test func liveEchoCannotConsumeAnotherTurnOrAmbiguousReply() {
    let prompt = Message(role: "user", text: "one", sceneID: "s", sequence: 11)
    let live = Message(role: "being", text: "same", sceneID: "s", localBaseline: 10, replyTo: prompt.id, localAfter: prompt.id, streaming: true)
    let next = Message(role: "user", text: "two", sceneID: "s", sequence: 13)
    let other = Message(role: "being", text: "same prefix, different turn", sceneID: "s", sequence: 14)
    #expect(HistoryRules.merge([prompt, live], [prompt, next, other]).filter { $0.role == "being" }.count == 2)
    let a = Message(role: "being", text: "same one", sceneID: "s", sequence: 12)
    let b = Message(role: "being", text: "same two", sceneID: "s", sequence: 13)
    #expect(HistoryRules.merge([prompt, live], [prompt, a, b]).filter { $0.role == "being" }.count == 3)
}

@Test func cachedDuplicateAfterCompletionMergesWithoutTakingAnotherTurn() {
    let prompt = Message(role: "user", text: "question", sceneID: "s", sequence: 11)
    let local = Message(role: "being", text: "answer", sceneID: "s", localBaseline: 10, replyTo: prompt.id, localAfter: prompt.id, streaming: false)
    let remote = Message(role: "being", text: "answer", sceneID: "s", sequence: 12)
    #expect(HistoryRules.merge([prompt, remote, local], [remote]).filter { $0.role == "being" }.count == 1)
    let next = Message(role: "user", text: "next question", sceneID: "s", sequence: 12)
    var later = remote; later.sequence = 13
    #expect(HistoryRules.merge([prompt, local], [next, later]).filter { $0.role == "being" }.count == 2)
}
