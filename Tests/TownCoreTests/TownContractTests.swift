import Foundation
import Testing
@testable import TownCore
@Test func pairingWaitsForCompleteAssistantReply() throws {
    var c = PairCodeCollector(sceneID: "pair-1")
    #expect(try c.consume(SSEEvent(name:"tool_result",data:"{\"text\":\"WRONG1\"}")) == nil)
    #expect(try c.consume(SSEEvent(name:"content_block_delta",data:"{\"scene_id\":\"other\",\"delta\":{\"text\":\"WRONG2\"}}")) == nil)
    #expect(try c.consume(SSEEvent(name:"content_block_delta",data:"{\"delta\":{\"text\":\"AB3\"}}")) == nil)
    #expect(try c.consume(SSEEvent(name:"content_block_delta",data:"{\"delta\":{\"text\":\"XY9\"}}")) == nil)
    #expect(try c.consume(SSEEvent(name:"message_stop",data:"{}")) == "AB3XY9")
}
@Test func pairingDoesNotJoinRepliesOrAcceptAmbiguity() throws {
    var c = PairCodeCollector(sceneID:"pair")
    _ = try c.consume(SSEEvent(name:"content_block_delta",data:"{\"delta\":{\"text\":\"ABC\"}}"))
    #expect(try c.consume(SSEEvent(name:"message_stop",data:"{}")) == nil)
    _ = try c.consume(SSEEvent(name:"content_block_delta",data:"{\"delta\":{\"text\":\"123\"}}"))
    #expect(try c.consume(SSEEvent(name:"message_stop",data:"{}")) == nil)
    _ = try c.consume(SSEEvent(name:"content_block_delta",data:"{\"delta\":{\"text\":\"ABC123 DEF456\"}}"))
    #expect(throws: PortalError.self) { try c.consume(SSEEvent(name:"message_stop",data:"{}")) }
}
@Test func townIdentityIsCaseSensitiveAndPairBound() throws {
    #expect(try TownContracts.identity(" Willow ") == "willow")
    #expect(try TownContracts.identity("t_Willow") == "t_Willow")
    let token = "abcdefghijklmnop"
    try TownContracts.validatePair(input:"t_Will",townID:"t_Willow",beingID:"willow",token:token)
    #expect(throws: PortalError.self) { try TownContracts.validatePair(input:"t_will",townID:"t_Willow",beingID:nil,token:token) }
    #expect(throws: PortalError.self) { try TownContracts.validatePair(input:"willow",townID:"t_Willow",beingID:"other",token:token) }
    #expect(throws: PortalError.self) { try TownContracts.validatePair(input:"willow",townID:"../path",beingID:"willow",token:token) }
}
@Test func pairingSupportsDesktopEventVariants() throws {
    var c = PairCodeCollector(sceneID: "pair")
    #expect(try c.consume(SSEEvent(name:"message",data:#"{"type":"text","text":"AB3XY9"}"#)) == nil)
    #expect(try c.consume(SSEEvent(name:"message",data:#"{"type":"message_stop"}"#)) == "AB3XY9")
    var d = PairCodeCollector(sceneID: "pair")
    _ = try d.consume(SSEEvent(name:"text",data:#"{"text":"AB3XY9"}"#))
    #expect(try d.consume(SSEEvent(name:"message",data:"[DONE]")) == "AB3XY9")
}
@Test func pairingAcceptsCompleteReplyAtEOF() throws {
    var c = PairCodeCollector(sceneID:"pair")
    _ = try c.consume(SSEEvent(name:"message",data:#"{"content":"AB3XY9"}"#))
    #expect(try c.finish() == "AB3XY9")
}
@Test func sceneNamesAndTransportCuesMatchDesktop() {
    #expect(SceneRules.validID("desktop-abc:room/1"))
    #expect(!SceneRules.validID("other room"))
    #expect(!SceneRules.validName("two\nlines"))
    #expect(SceneRules.validName("方案讨论"))
    #expect(SceneRules.stripTransition("【新消息来自 scene「方案讨论 · ID: desktop-1」】\n\n你好") == "你好")
    #expect(SceneRules.stripTransition("正文中的【新消息来自 scene「x」】") == "正文中的【新消息来自 scene「x」】")
}
@Test func partialHistoryPreservesLocalContentAndRepeatedEchoes() {
    let old = Message(role:"being",text:"older",sceneID:"a",sequence:1)
    let pending = Message(role:"user",text:"again",sceneID:"a")
    let incoming = Message(role:"user",text:"again",sceneID:"a",sequence:2)
    let result = HistoryRules.merge([old,pending,pending], [incoming])
    #expect(result.map(\.text) == ["older","again","again"])
    #expect(result.last?.sequence == nil)
    #expect(HistoryRules.merge(result,[incoming]).count == 3)
    let otherScene = Message(role:"user",text:"again",sceneID:"b")
    #expect(HistoryRules.merge([otherScene],[incoming]).count == 2)
}
@Test func socialNewestFirstAndAnnouncementAllCategory() {
    let rows:[[String:Any]] = [
        ["seq":1,"at":"2026-10-14T12:00:00Z"],
        ["seq":3,"created_at":"2026-10-14T20:01:00+08:00"],
        ["seq":2,"at":"2026-10-14T12:01:00Z"]]
    #expect(FeedRules.newestFirst(rows).compactMap { $0["seq"] as? Int } == [3,2,1])
    #expect(!FeedRules.announcementQuery(category:"",includeExpired:false).contains { $0.name == "category" })
    #expect(FeedRules.announcementQuery(category:"update",includeExpired:false).contains { $0.name == "category" && $0.value == "update" })
}
@Test func structuredRenderingPreservesJSONSource() {
    let json = #"{"id":9007199254740993123,"id":2,"text":"a\\b\n","empty":[]}"#
    #expect(StructuredText.detect(json) == "json")
    let pretty = StructuredText.formatJSON(json)
    #expect(pretty?.contains("9007199254740993123") == true)
    #expect(pretty?.components(separatedBy:"\"id\"").count == 3)
    #expect(pretty?.contains(#"a\\b\n"#) == true)
    #expect(StructuredText.detect("{\"a\":1}\n{\"b\":2}") == "jsonl")
    #expect(StructuredText.detect("{\"a\":" ) == nil)
    #expect(StructuredText.detect("123") == nil)
    #expect(MarkdownBlocks.parse(json).first?.kind == .code)
}
@Test func beingReplyIncludesParentAndOriginalMessage() {
    let row:[String:Any] = ["reply_to":7,"reply_to_display":"同伴"]
    let context=ReplyRules.context(row,rows:[["seq":7,"message":"上文内容"]])
    #expect(context == "同伴：上文内容")
    let prompt=ReplyRules.prompt(place:"围炉「测试」",author:"作者",content:"原文",context:context,description:"")
    #expect(prompt.contains("这条消息所回复的上文：\n> 同伴：上文内容"))
    #expect(prompt.contains("回复对象：作者"))
    #expect(prompt.contains("要回复的原消息：\n> 原文"))
    #expect(!prompt.contains("我已经手写"))
    #expect(ReplyRules.context([:]) == nil)
}

@Test func historyDropsEmptyReplyPlaceholdersWithoutDroppingPartialText() {
    let pending = [Message(role:"being",text:"",sceneID:"a"), Message(role:"being",text:"partial",sceneID:"a")]
    let confirmed = [Message(role:"being",text:"reply",sceneID:"a",sequence:1)]
    #expect(HistoryRules.merge(pending, confirmed).map(\.text) == ["reply", "partial"])
    #expect(HistoryRules.merge(pending, []).map(\.text) == ["partial"])
}

@Test func memberFormatsAndIdentityDeduplication() throws {
    let payload: [Any] = ["legacy", ["id":"t_1","displayName":"Same"], ["town_id":"t_2","display":"Same","joinedAt":"2026-10-14"], ["being_id":"t_1","name":"Duplicate"], 42, NSNull()]
    let members = try TownContracts.members(["members":payload])
    #expect(members.map(\.id) == ["legacy","t_1","t_2","42"])
    #expect(members[1].name == members[2].name)
    #expect(members[2].joinedAt == "2026-10-14")
    #expect(try TownContracts.members(payload) == members)
    #expect(throws: PortalError.self) { try TownContracts.members(["members":"invalid"]) }
    #expect(TownContracts.authorKey("t_123") == "author")
    #expect(TownContracts.authorKey("legacy_being") == "being_id")
}
