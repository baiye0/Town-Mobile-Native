import Testing
@testable import TownCore
@Test func connectionValidation() throws {
    let c = try Connection("https://example.com/willow/?token=abc_123&relay_secret=xyz")
    #expect(c.endpoint == "https://example.com/willow")
    #expect(c.secret == "xyz")
    #expect(c.url("/api/history?limit=100").query?.contains("limit=100&token=abc_123") == true)
    for link in ["http://example.com/a?token=x", "https://u:p@example.com/a?token=x", "https://example.com/a/b?token=x", "https://example.com/a?token=", "https://example.com/a?token=x&secret=%0d"] {
        #expect(throws: PortalError.self) { try Connection(link) }
    }
}
@Test func sseFraming() {
    var p = SSEParser()
    #expect(p.line(": keepalive") == nil)
    #expect(p.line("event: content_block_delta\r") == nil)
    #expect(p.line("data: {\"delta\":") == nil)
    #expect(p.line("data: {\"text\":\"你好\"}}") == nil)
    #expect(p.line("") == SSEEvent(name: "content_block_delta", data: "{\"delta\":\n{\"text\":\"你好\"}}"))
    #expect(p.line("") == nil)
    _ = p.line("data: next")
    #expect(p.line("")?.name == "message")
}

@Test func sseBytesPreserveBlankFramesAndUTF8() throws {
    let wire = "event: text\r\ndata: {\"text\":\"你好 AB3XY9\"}\r\n\r\nevent: message_stop\ndata: {}\n\n"
    var parser = SSEByteParser()
    var events: [SSEEvent] = []
    for byte in wire.utf8 { if let event = try parser.consume(byte) { events.append(event) } }
    #expect(events.count == 2)
    #expect(events[0].name == "text")
    #expect(events[0].data == #"{"text":"你好 AB3XY9"}"#)
    #expect(events[1].name == "message_stop")
}
@Test func pairingConsumesActualSSEBytes() throws {
    var parser = SSEByteParser()
    var collector = PairCodeCollector(sceneID:"pair")
    var result: String?
    let wire = "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"AB3XY9\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n"
    for byte in wire.utf8 { if let event = try parser.consume(byte) { result = try collector.consume(event) ?? result } }
    #expect(result == "AB3XY9")
}
@Test func markdownBlocksKeepCodeAndTablesDistinct() {
    let blocks = MarkdownBlocks.parse("# 标题\n\n- **项目**\n  - 子项\n\n| 名称 | 值 |\n| --- | --- |\n| a | `b|c` |\n\n```swift\nlet x = \"# raw\"\n```\n> 引用")
    #expect(blocks.map(\.kind) == [.heading,.list,.list,.table,.code,.quote])
    #expect(blocks[3].rows[1][1] == "`b|c`")
    #expect(blocks[4].text == "let x = \"# raw\"")
}
@Test func historyDoesNotDropSelfOrSystemMarkers() {
    #expect(HistoryRules.role("self") == "being")
    #expect(HistoryRules.marker("[breath yielded: next]") == "放下手头的事，转向你")
    #expect(HistoryRules.text([["text":"a"],["text":"b"]]) == "a\n\nb")
}
