import Foundation
import Testing
@testable import TownCore

private let imageReceipt = #"{"type":"being.image-generation","version":1,"being_id":"willow","jobs":[{"index":1,"title":"图片","submission":"accepted","generation_id":"gen_one","client_request_id":"request_one","error_code":null}]}"#

@Test func imageReceiptValidation() {
    #expect(ImageGeneration.parse(imageReceipt) != nil)
    for bad in [imageReceipt.replacingOccurrences(of: #""version":1"#, with: #""version":true"#), imageReceipt.replacingOccurrences(of: #""index":1"#, with: #""index":"1""#), imageReceipt.replacingOccurrences(of: #""gen_one""#, with: "null"), imageReceipt.replacingOccurrences(of: #""being_id":"#, with: #""extra":1,"being_id":"#)] { #expect(ImageGeneration.parse(bad) == nil) }
}
@Test func imageReceiptBoundaries() {
    let parts = ImageGeneration.parts("前文\n```json\n\(imageReceipt)\n```\n后文")
    #expect(parts.map(\.receipt) == [false, true, false])
    #expect(parts.first?.text == "前文\n"); #expect(parts.last?.text == "后文")
    for text in ["`\(imageReceipt)`", "> \(imageReceipt)", "```python\n\(imageReceipt)\n```", "{\"example\":\(imageReceipt)}"] { #expect(!ImageGeneration.parts(text).contains { $0.receipt }) }
    #expect(ImageGeneration.parts(String(imageReceipt.dropLast(3))).first?.receipt == true)
    #expect(ImageGeneration.parse(String(imageReceipt.dropLast(3))) == nil)
}
@Test func generationPollingBounds() {
    let queued = GenerationSnapshot(id: "gen_one", status: "queued", deadline: 100000, delay: 0, action: false, images: [], availability: "pending")
    #expect(queued.wait(0) == 1000); #expect(queued.wait(99500) == 500); #expect(queued.wait(100000) == nil)
    for status in ["succeeded", "failed", "cancelled", "uncertain"] {
        #expect(GenerationSnapshot(id: "gen_one", status: status, deadline: 100000, delay: 1000, action: false, images: [], availability: "pending").wait(0) == nil)
    }
}
@Test func markdownImageBoundariesAndSignedURLs() {
    let url = "https://example.com/a(b).png?token=a%2Bb%3D&x=1"
    let blocks = MarkdownBlocks.parse("前 ![照片](\(url)) 后\n\n![引用][pic]\n\n[pic]: <\(url)>\n\n`![代码](\(url))`\n\n```md\n![代码](\(url))\n```")
    #expect(blocks.filter { $0.kind == .image }.map(\.text) == [url, url])
    #expect(blocks.contains { $0.kind == .paragraph && $0.text.contains("前 ") })
    #expect(blocks.contains { $0.kind == .code && $0.text.contains("![代码]") })
}

@Test func generationManifestIdentityAndOrigin() throws {
    let raw = #"{"id":"gen_one","client_request_id":"request_one","status":"succeeded","stage":"done","deadline":9999999999999,"poll_after_ms":10,"required_action":null,"error_code":null,"availability":"available","manifest":{"version":1,"kind":"image","outputs":[{"id":"out","mime":"image/png","attachment":{"source":"being-service","attachment_id":"att_one"},"view_url":"https://beings.town/api/being-service/v1/assets/att_one/view?token=a%2Bb%3D&x=1"}]}}"#
    let job = try #require(ImageGeneration.parse(imageReceipt)?.jobs.first)
    func parse(_ text: String) throws -> GenerationSnapshot {
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        return try ImageGeneration.snapshot(object, job: job)
    }
    #expect(try parse(raw).images.first?.url.hasSuffix("token=a%2Bb%3D&x=1") == true)
    for bad in [raw.replacingOccurrences(of: "gen_one", with: "gen_other"), raw.replacingOccurrences(of: "request_one", with: "other"), raw.replacingOccurrences(of: "https://beings.town/", with: "https://evil.example/"), raw.replacingOccurrences(of: "att_one/view", with: "att_other/view"), raw.replacingOccurrences(of: #""poll_after_ms":10"#, with: #""poll_after_ms":"10""#)] {
        #expect(throws: PortalError.self) { try parse(bad) }
    }
}

@Test func markdownReferencesCrossReceiptBoundaries() {
    let text = "![照片][pic]\n\n\(imageReceipt)\n\n[pic]: https://example.com/a.png\n\n```md\n[bad]: https://example.com/b.png\n```"
    let definitions = MarkdownImages.definitions(text)
    #expect(!definitions.contains("[bad]"))
    let first = ImageGeneration.parts(text).first?.text ?? ""
    #expect(MarkdownBlocks.parse(first, imageReferences: definitions).first { $0.kind == .image }?.text == "https://example.com/a.png")
}

@Test func nestedArrayExamplesNeverTriggerQueries() {
    #expect(!ImageGeneration.parts("```json\n[\n\(imageReceipt)\n]\n```").contains { $0.receipt })
    for array in ["[\n\(imageReceipt)\n]", "[true,\n\(imageReceipt)\n]", "[\"example\",\n\(imageReceipt)\n]", "[\n[\n\(imageReceipt)\n]\n]"] {
        let parts = ImageGeneration.parts("示例：\n\(array)\n\n实际回执：\n\(imageReceipt)")
        #expect(parts.filter(\.receipt).count == 1)
        #expect(parts.first?.text == "示例：\n\(array)\n\n实际回执：\n")
    }
    #expect(ImageGeneration.parts("[pic]: https://example.com/a.png\n\(imageReceipt)").filter(\.receipt).count == 1)
}

@Test func referenceContextDoesNotAlterCodeOrStreamingText() {
    let definitions = "[pic]: https://example.com/a.png"
    let blocks = MarkdownBlocks.parse("![照片][pic]\n\n```text\n尚未闭合", imageReferences: definitions)
    #expect(blocks.first { $0.kind == .image }?.text == "https://example.com/a.png")
    #expect(blocks.last?.kind == .code)
    #expect(blocks.last?.text == "尚未闭合")
    #expect(MarkdownBlocks.parse(#"{"key":1}"#, imageReferences: definitions).first?.text == #"{"key":1}"#)
}
