import Foundation
import Testing
@testable import TownCore

@Test func historyRefreshPreservesBubbleIdentityAndMetadata() {
    let local = Message(role: "user", text: "hello", sceneID: "a", process: "details", localBaseline: 10)
    let remote = Message(role: "user", text: "hello", sceneID: "a", sequence: 11, timestamp: "2026-10-19T01:00:00Z")
    let first = HistoryRules.merge([local], [remote])
    #expect(first.count == 1)
    #expect(first[0].id == local.id)
    #expect(first[0].timestamp == remote.timestamp)
    let second = HistoryRules.merge(first, [remote])
    #expect(second[0].id == local.id)
    #expect(second[0].process == "details")
}

@Test func pendingMessagesStayAtTheirHistoryPositionAcrossScenes() {
    let old = Message(role: "user", text: "old", sceneID: "a", sequence: 10)
    let later = Message(role: "user", text: "later", sceneID: "b", sequence: 20)
    let pending = Message(role: "user", text: "pending", sceneID: "a", timestamp: "2026-10-19T01:00:00Z", localBaseline: 10)
    let reply = Message(role: "being", text: "partial", sceneID: "a", timestamp: pending.timestamp, localBaseline: 10)
    let other = Message(role: "user", text: "other scene", sceneID: "b", timestamp: "2026-10-19T01:01:00Z", localBaseline: 10)
    let merged = HistoryRules.merge([other, pending, reply], [later, old])
    #expect(merged.map(\.text) == ["old", "pending", "partial", "other scene", "later"])
    let earlierEcho = Message(role: "user", text: "pending", sceneID: "a", sequence: 9)
    #expect(HistoryRules.merge([pending], [earlierEcho]).count == 2)
}

@Test func legacyToolReplyIsReconciledWithoutLosingItsPrefix() {
    let final = String(repeating: "final answer. ", count: 30)
    let historical = Message(role: "being", text: final, sceneID: "a", sequence: 11)
    let stale = Message(role: "being", text: "Checking the tool first.\n" + final, sceneID: "a")
    let latest = Message(role: "user", text: "latest", sceneID: "a", sequence: 30)
    let merged = HistoryRules.merge([historical, latest, stale], [historical, latest])
    #expect(merged.map(\.sequence) == [11, 30])
    #expect(merged[0].id == historical.id)
    #expect(merged[0].process == "Checking the tool first.")
    #expect(HistoryRules.merge(merged, [historical, latest])[0].process == merged[0].process)
    #expect(HistoryRules.merge([stale], [historical], activeIDs: [stale.id]).count == 2)
    let other = Message(role: "being", text: final, sceneID: "b", sequence: 12)
    #expect(HistoryRules.merge([stale], [other]).count == 2)
    let duplicate = Message(role: "being", text: final, sceneID: "a", sequence: 13)
    #expect(HistoryRules.merge([stale], [historical, duplicate]).count == 3)
    #expect(HistoryRules.merge([Message(role: "being", text: "prefix short", sceneID: "a")], [Message(role: "being", text: "short", sceneID: "a", sequence: 1)]).count == 2)
}
