import Foundation
import Testing
@testable import TownCore

@Test func markdownImagesPreserveSignedURLAndSurroundingText() {
    let url = URL(string: "https://images.example/view?token=a%2Fb%2Bc&expires=123")!
    #expect(MarkdownImages.parse("前文 ![预览](\(url.absoluteString)) 后文") == [.text("前文 "), .image(alt: "预览", url: url), .text(" 后文")])
}

@Test func markdownImagesHandleBalancedURLsTitlesAndMultipleImages() {
    let a = URL(string: "https://example.com/a_(b).png")!
    let b = URL(string: "https://example.com/b.png?q=1&x=2")!
    #expect(MarkdownImages.parse(#"![a](https://example.com/a_(b).png "标题") ![]( <https://example.com/b.png?q=1&x=2> )"#) == [.image(alt: "a", url: a), .text(" "), .image(alt: "", url: b)])
    #expect(MarkdownImages.parse(#"![a\]b](https://example.com/a_\(b\).png)"#) == [.image(alt: "a]b", url: a)])
}

@Test func markdownImagesLeaveCodeEscapesAndIncompleteStreamsAlone() {
    for text in [#"`![code](https://example.com/a.png)`"#, #"\![escaped](https://example.com/a.png)"#, "![partial](https://example.com/a.png", "![partial", "![a](https://example.com/a.png \"unfinished"] {
        #expect(MarkdownImages.parse(text) == [.text(text)])
    }
    let text = "![photo](https://example.com/a.png)"
    for end in text.indices.dropFirst() { #expect(MarkdownImages.parse(String(text[..<end])).allSatisfy { if case .text = $0 { return true }; return false }) }
    #expect(MarkdownImages.parse(text) == [.image(alt: "photo", url: URL(string: "https://example.com/a.png")!)])
    #expect(MarkdownBlocks.parse("```md\n\(text)\n```").first?.kind == .code)
}

@Test func markdownImagesRejectNonWebAndCredentialURLs() {
    for target in ["file:///tmp/photo.png", "data:image/png;base64,abc", "javascript:alert(1)", "https://user:pass@example.com/a.png", "/local/image.png"] {
        let text = "![a](\(target))"
        #expect(MarkdownImages.parse(text) == [.text(text)])
    }
}
