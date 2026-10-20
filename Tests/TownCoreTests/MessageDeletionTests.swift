import Foundation
import Testing
@testable import TownCore

@Test func deletedAttachmentStaysHiddenAfterHistoryRefreshAndRestart() throws {
    let reference = "[attachment-message:v1:msg_" + String(repeating: "a", count: 64) + "]"
    let pending = Message(role: "user", text: "photo\n" + reference, sceneID: "scene", localBaseline: 10)
    let persisted = try JSONEncoder().encode([MessageDeletion(pending, endpoint: "being-a")])
    let deletions = try JSONDecoder().decode([MessageDeletion].self, from: persisted)
    let echoed = Message(role: "user", text: "normalized context\n" + reference, sceneID: "scene", sequence: 11)
    let merged = HistoryRules.merge([pending], [echoed])
    #expect(merged.filter { message in !deletions.contains { $0.matches(message, endpoint: "being-a") } }.isEmpty)
    #expect(deletions[0].matches(echoed, endpoint: "being-a"))
    #expect(!deletions[0].matches(echoed, endpoint: "being-b"))
    var otherScene = echoed; otherScene.sceneID = "another"
    #expect(!deletions[0].matches(otherScene, endpoint: "being-a"))
    var earlier = echoed; earlier.sequence = 9
    #expect(!deletions[0].matches(earlier, endpoint: "being-a"))
    var reply = echoed; reply.role = "being"
    #expect(!deletions[0].matches(reply, endpoint: "being-a"))
}

@Test func deletingFailedTextDoesNotHideAnotherIdenticalSend() {
    let failed = Message(role: "user", text: "hello", sceneID: "scene")
    let deleted = MessageDeletion(failed, endpoint: "being")
    #expect(deleted.matches(failed, endpoint: "being"))
    #expect(!deleted.matches(Message(role: "user", text: "hello", sceneID: "scene"), endpoint: "being"))
}

@Test func deletingConfirmedAttachmentUsesSequenceWithoutHidingReuse() {
    let reference = "[attachment-message:v1:msg_" + String(repeating: "b", count: 64) + "]"
    let original = Message(role: "user", text: reference, sceneID: "scene", sequence: 12)
    let deleted = MessageDeletion(original, endpoint: "being")
    var reloaded = original; reloaded.id = UUID()
    #expect(deleted.matches(reloaded, endpoint: "being"))
    reloaded.sequence = 13
    #expect(!deleted.matches(reloaded, endpoint: "being"))
}
