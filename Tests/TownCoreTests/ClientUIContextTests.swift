import Foundation
import Testing
@testable import TownCore

@Test func hidesVersionIndependentDesktopAndMobileContext() {
    for body in ["旧客户端协议", "新客户端协议\n图片、tabs、app 等"] {
        let text = "请修改计划\r\n\r\n[客户端 Intelligent UI Beta 上下文]\r\n\(body)\r\n[/客户端 Intelligent UI Beta 上下文]\r\n\r\n[客户端当前界面选择]\r\n{\"revision\":2}\r\n[/客户端当前界面选择]"
        #expect(DeliveryRules.displayText(text) == "请修改计划")
        #expect(DeliveryRules.matchesSubmittedText(text, text.replacingOccurrences(of: body, with: "另一个版本")))
    }
}
@Test func selectionStillDistinguishesSubmissionIdentity() {
    let first = "继续\n\n[客户端当前界面选择]\n{\"count\":1}\n[/客户端当前界面选择]"
    #expect(!DeliveryRules.matchesSubmittedText(first, first.replacingOccurrences(of: ":1", with: ":2")))
    #expect(ClientUIContext.strip(first) == "继续")
}
@Test func preservesIncompleteQuotedAndUnrelatedContent() {
    let snippet = "```text\n[客户端当前界面选择]\n示例\n[/客户端当前界面选择]\n```"
    #expect(ClientUIContext.strip(snippet) == snippet)
    let incomplete = "提问\n\n[客户端当前界面选择]\n还未结束"
    #expect(ClientUIContext.strip(incomplete) == incomplete)
    #expect(ClientUIContext.strip("普通提问 [客户端当前界面选择] 不删除") == "普通提问 [客户端当前界面选择] 不删除")
    #expect(ClientUIContext.strip("前文\n\n[客户端界面操作]\n{}\n[/客户端界面操作]\n后文") == "前文\n\n后文")
}
@Test func persistsUISelectionInPendingQueue() throws {
    var entry = PendingSend(endpoint: "https://example.test", sceneID: "one", title: "One", text: "继续")
    entry.intelligentUISelection = "{\"surfaceId\":\"plan\",\"revision\":2}"
    let restored = try JSONDecoder().decode(PendingSend.self, from: JSONEncoder().encode(entry))
    #expect(restored.intelligentUISelection == entry.intelligentUISelection)
}
