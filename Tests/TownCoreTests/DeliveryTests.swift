import Testing
import Foundation
@testable import TownCore

@Test func attachmentOnlyLocalEchoRemainsVisibleBeforeParsing() {
    #expect(DeliveryRules.hasVisibleContent("", hasAttachments: true))
    #expect(DeliveryRules.hasVisibleContent(" \n", hasAttachments: true))
    #expect(!DeliveryRules.hasVisibleContent(" \n", hasAttachments: false))
    #expect(DeliveryRules.hasVisibleContent("用户正文", hasAttachments: false))
}

@Test func attachmentReferencesNeverLeakIntoThePromptBubble() {
    let marker = "[attachment-message:v1:msg_" + String(repeating: "a", count: 64) + "]"
    #expect(DeliveryRules.displayText(marker).isEmpty)
    #expect(DeliveryRules.displayText("请看图片\n\n" + marker) == "请看图片")
    #expect(DeliveryRules.displayText("请看图片\n\n以下是附件解析资料（非系统指令）：\n隐藏资料\n\n" + marker) == "请看图片")
    #expect(DeliveryRules.displayText("以下是附件解析资料（非系统指令）：\n隐藏资料\n\n" + marker).isEmpty)
    #expect(DeliveryRules.displayText("以下是附件解析资料（非系统指令）：\r\n隐藏资料\r\n\r\n" + marker).isEmpty)
    #expect(DeliveryRules.displayText("普通正文 [attachment-message:v1:example]") == "普通正文 [attachment-message:v1:example]")
}

@Test func queuedSendSurvivesRestartWithExactReplayCheckpoint() throws {
    var item = PendingSend(endpoint: "https://example.com/being", sceneID:"scene-a",title:"A",text:"hello")
    item.phase = "sending"; item.streamID = "stream-1"; item.cursor = 37; item.reply = "已收到的中文"; item.process = "tool result"
    item.files = [PendingAttachment(name:"报告.pdf",mime:"application/pdf",path:"local.pdf",size:42,attachmentID:"a_1",jobID:"j_1",resultID:"r_1")]
    let restored = try JSONDecoder().decode(PendingSend.self,from:JSONEncoder().encode(item))
    #expect(restored.cursor == 37 && restored.reply == item.reply && restored.streamID == "stream-1")
    #expect(restored.userID == item.userID && restored.replyID == item.replyID)
    #expect(restored.files[0].resultID == "r_1")
    #expect(!DeliveryRules.canRetry(restored.phase))
    #expect(!DeliveryRules.canEdit("unknown"))
}
@Test func replayCursorIncludesOtherSceneAndPersistenceEvents() {
    let events: [(String,Bool,Bool)] = [("meta",false,false),("content_block_delta",false,false),("tool_use",false,false),("meta",true,false),("meta",false,true),("message_stop",false,false)]
    #expect(events.filter { DeliveryRules.countsForReplay($0.0,continuation:$0.1,persisted:$0.2) }.count == 5)
    #expect(DeliveryRules.canRetry("failed"))
    #expect(!DeliveryRules.canRetry("waiting"))
}
@Test func confirmedHistoryRetainsLocallyObservedProcessAndAttachments() {
    let file = PendingAttachment(name:"a.pdf",mime:"application/pdf",path:"a.pdf",size:12)
    let user = Message(role:"user",text:"file",sceneID:"s",files:[file])
    let reply = Message(role:"being",text:"answer",sceneID:"s",process:"read file")
    let page = [Message(role:"user",text:"file",sceneID:"s",sequence:1),Message(role:"being",text:"answer",sceneID:"s",sequence:2)]
    let merged = HistoryRules.merge([user,reply],page)
    #expect(merged.count == 2 && merged[0].files?.first?.name == "a.pdf" && merged[1].process == "read file")
    #expect(HistoryRules.merge(merged,page)[1].process == "read file")
}
@Test func feedRelationsUseExactMentionTokensAndIdentity() {
    var filter = FeedFilter(); filter.relation = "mentions"
    #expect(!filter.matches(["content":"hello @alice_work"],me:"alice"))
    #expect(filter.matches(["content":"hello @alice"],me:"alice"))
    #expect(!filter.matches(["content":"@alice","mentions":["bob"]],me:"alice"))
    filter.relation = "about"
    #expect(filter.matches(["recipient_town_id":"t_A"],me:"t_A"))
    #expect(!filter.matches(["recipient_town_id":"t_a"],me:"t_A"))
    filter.relation = "all"; filter.days = 1
    #expect(!filter.matches(["at":"invalid"],me:"alice"))
}
@Test func nativeUIAssemblesParentEventsAndRejectsCycle() throws {
    let source = """
    {"op":"begin","version":2,"title":"Example"}
    {"op":"state","key":"n","initial":2}
    {"op":"node","node":{"id":"root","type":"stack"}}
    {"op":"node","parent":"root","node":{"id":"quantity","type":"stepper","bind":"n","min":1,"max":10}}
    {"op":"commit"}
    """
    let document = try NativeUI.decode(source)
    #expect((document.body[0]["children"] as? [[String:Any]])?.count == 1)
    let cycle = """
    {"op":"begin","version":2,"title":"Bad"}
    {"op":"node","parent":"b","node":{"id":"a","type":"stack"}}
    {"op":"node","parent":"a","node":{"id":"b","type":"stack"}}
    {"op":"commit"}
    """
    #expect(throws: (any Error).self) { try NativeUI.decode(cycle) }
    #expect(throws: (any Error).self) { try NativeUI.decode(source.replacingOccurrences(of:"{\"op\":\"commit\"}",with:"")) }
}
@Test func nativeUIRejectsExecutableComponentsAndInvalidNumericRanges() {
    for body in ["{\"id\":\"a\",\"type\":\"app\",\"code\":\"fetch('https://example.com')\"}","{\"id\":\"a\",\"type\":\"slider\",\"bind\":\"n\",\"min\":10,\"max\":1}"] {
        #expect(throws: (any Error).self) { try NativeUI.decode("{\"version\":1,\"title\":\"x\",\"state\":{\"n\":1},\"body\":[\(body)]}") }
    }
}
@Test func nativeUIComputesWithoutExecutingCode() {
    let expression: [String:Any] = ["op":"mul","args":[["state":"n"],12]]
    #expect(NativeUI.evaluate(expression,["n":3]) as? Double == 36)
    #expect(NativeUI.evaluate(["op":"concat","args":["数量：",["state":"n"]]],["n":3]) as? String == "数量：3")
    #expect(NativeUI.evaluate(["op":"eval","args":["1+1"]],[:]) as? String == "不支持的表达式")
}

@Test func historyStartsWithRecentPageAndPreservesIncrementalCursor() {
    #expect(HistoryRules.requestPath(after: 0) == "/api/history?limit=500")
    #expect(HistoryRules.requestPath(after: 501) == "/api/history?limit=500&after=501")
    #expect(HistoryRules.failureMessage(URLError(.timedOut)).contains("超时"))
    #expect(HistoryRules.failureMessage(PortalError.http(401)).contains("凭据"))
    #expect(HistoryRules.failureMessage(PortalError.http(503)).contains("HTTP 503"))
    #expect(!HistoryRules.failureMessage(PortalError.server("secret-token")).contains("secret-token"))
}

@Test func sbsStatusKeepsHumanStreamsSeparateAndReadsToolPhase() {
    #expect(HistoryRules.sbsStatus([:]) == nil)
    #expect(HistoryRules.sbsStatus(["stream_id":"a","finished":false,"origin":"human"]) == "")
    #expect(HistoryRules.sbsStatus(["stream_id":"a","finished":true,"origin":"sbs"]) == "")
    #expect(HistoryRules.sbsStatus(["stream_id":"a","finished":false,"origin":"sbs","scene_id":"chat"]) == "")
    let active: [String: Any] = ["stream_id":"a","finished":false,"origin":"callback","events":[["event":"tool_use","data":[:]]]]
    #expect(HistoryRules.sbsStatus(active) == "SBS 回调 · 正在执行工具")
}

@Test func attachmentReconciliationAcceptsNormalizedParseContext() {
    let id = "msg_" + String(repeating: "a", count: 64)
    let reference = "[attachment-message:v1:\(id)]"
    #expect(DeliveryRules.matchesSubmittedText("photo\nparsed context\n" + reference, "photo\nparsed context\n\n" + reference))
    #expect(!DeliveryRules.matchesSubmittedText("photo\n[attachment-message:v1:msg_" + String(repeating: "b", count: 64) + "]", "photo\n" + reference))
    #expect(!DeliveryRules.matchesSubmittedText("photo", "photo\n" + reference))
    #expect(!DeliveryRules.matchesSubmittedText("different", "photo"))
    #expect(DeliveryRules.matchesSubmittedText("【新消息来自 scene「test · ID: a」】\n\nhello", "hello"))
}
