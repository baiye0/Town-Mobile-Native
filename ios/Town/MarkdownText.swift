import SwiftUI

struct MarkdownText: View {
    @AppStorage("reading.size") private var readingSize = 16.0
    let text: String
    var previewMarkdownCode = true
    var foreground: Color? = nil
    var fillsWidth = true
    var imageReferences = ""
    @State private var parsed: [MarkdownBlock]?
    private var parseKey: MarkdownParseKey { MarkdownParseKey(text: text, references: imageReferences) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Start small documents with their real block structure. A tall raw
            // code placeholder that later collapses can strand LazyVStack at a
            // blank estimated offset. Subsequent stream frames parse off-thread.
            ForEach(Array((parsed ?? MarkdownInitialCache.blocks(parseKey)).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, readingSize: readingSize,
                                  previewMarkdownCode: previewMarkdownCode, foreground: foreground).equatable()
            }
        }.foregroundStyle(foreground ?? ClientTheme.text).frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in ["https", "http"].contains(url.scheme ?? "") && url.user == nil && url.password == nil ? .systemAction : .discarded })
            .task(id: parseKey) {
                let result = await MarkdownBlockParser.shared.parse(parseKey)
                guard !Task.isCancelled else { return }
                parsed = result
            }
    }
}

private struct MarkdownBlockView: View, Equatable {
    let block: MarkdownBlock
    let readingSize: Double
    let previewMarkdownCode: Bool
    let foreground: Color?
    @ViewBuilder private func inline(_ text: String) -> some View {
        let parts = MarkdownImages.parse(text)
        if parts.count == 1, case .text(let plain) = parts[0] {
            MarkdownInlineText(text: plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let text):
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            MarkdownInlineText(text: text)
                        }
                    case .image(let alt, let url): MarkdownImageView(alt: alt, url: url)
                    }
                }
            }
        }
    }
    var body: some View {
        Group {
                switch block.kind {
                case .image:
                    if let url = URL(string: block.text), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { MarkdownImageView(alt: block.label, url: url) }
                    else { RemoteImage(image: ChatImage(url: block.text, label: block.label)) }
                case .paragraph: inline(block.text).font(.system(size:readingSize)).lineSpacing(7).textSelection(.enabled)
                case .heading: inline(block.text).font(.system(size:block.level == 1 ? 20 : block.level == 2 ? 18 : 16,weight:.semibold)).padding(.top,8).textSelection(.enabled)
                case .list:
                    HStack(alignment:.top,spacing:8) { Text(block.label).frame(minWidth:18,alignment:.trailing); inline(block.text).frame(maxWidth:.infinity,alignment:.leading) }.font(.system(size:readingSize)).lineSpacing(6).padding(.leading,CGFloat(min(block.level,8))*16).textSelection(.enabled)
                case .quote:
                    HStack(alignment:.top,spacing:12) { Rectangle().fill(ClientTheme.secondary.opacity(0.3)).frame(width:3);inline(block.text).font(.system(size:readingSize)).lineSpacing(6).foregroundStyle(foreground ?? ClientTheme.secondary) }.fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                case .rule: Divider().padding(.vertical,8)
                case .code:
                    if block.label.lowercased() == "intelligent-ui" { NativeUIView(source: block.text) } else { NativeCodeBlock(text:block.text,language:block.label,allowPreview:previewMarkdownCode).foregroundStyle(ClientTheme.text) }
                case .table:
                    ScrollView(.horizontal) {
                        Grid(alignment:.topLeading,horizontalSpacing:0,verticalSpacing:0) {
                            ForEach(Array(block.rows.enumerated()),id:\.offset) { row,cells in
                                GridRow { ForEach(Array(cells.enumerated()),id:\.offset) { _,cell in inline(cell).foregroundStyle(ClientTheme.text).font(.system(size:13,weight:row==0 ? .semibold : .regular)).frame(width:150,alignment:.leading).padding(10).frame(maxHeight:.infinity,alignment:.top).background(row==0 ? ClientTheme.surface : ClientTheme.background).border(ClientTheme.secondary.opacity(0.15),width:0.5) } }
                            }
                        }.textSelection(.enabled)
                    }.clipShape(RoundedRectangle(cornerRadius:10)).padding(.vertical,4)
                }
        }
    }
}

@MainActor private enum MarkdownInitialCache {
    private final class Entry { let blocks: [MarkdownBlock]; init(_ blocks: [MarkdownBlock]) { self.blocks = blocks } }
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>(); cache.countLimit = 200; cache.totalCostLimit = 1_000_000; return cache
    }()
    static func blocks(_ key: MarkdownParseKey) -> [MarkdownBlock] {
        // Bound first-mount work; large documents retain a small preview until
        // the background parser returns instead of laying out the full source.
        guard key.text.utf8.count + key.references.utf8.count <= 8192 else {
            return [MarkdownBlock(kind: .paragraph, text: String(key.text.prefix(500)))]
        }
        let id = "\(key.text.utf8.count):\(key.text)\(key.references)" as NSString
        if let entry = cache.object(forKey: id) { return entry.blocks }
        let blocks = MarkdownBlocks.parse(key.text, imageReferences: key.references)
        cache.setObject(Entry(blocks), forKey: id, cost: (key.text.utf8.count + key.references.utf8.count) * 2)
        return blocks
    }
}

struct MarkdownParseKey: Hashable, Sendable { let text: String; let references: String }
actor MarkdownBlockParser {
    static let shared = MarkdownBlockParser()
    private final class Entry {
        let blocks: [MarkdownBlock]
        init(_ blocks: [MarkdownBlock]) { self.blocks = blocks }
    }
    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>(); cache.countLimit = 200; cache.totalCostLimit = 2_000_000; return cache
    }()
    func parse(_ key: MarkdownParseKey) -> [MarkdownBlock] {
        guard !Task.isCancelled else { return [] }
        let cacheKey = "\(key.text.utf8.count):\(key.text)\(key.references)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached.blocks }
        let blocks = MarkdownBlocks.parse(key.text, imageReferences: key.references)
        if !Task.isCancelled {
            cache.setObject(Entry(blocks), forKey: cacheKey, cost: (key.text.utf8.count + key.references.utf8.count) * 2)
        }
        return blocks
    }
}

struct NativeCodeBlock: View {
    let text:String
    let language:String
    let allowPreview:Bool
    @State private var source=false
    @State private var pretty=false
    @State private var highlighted: AttributedString?
    private var lang:String { language.isEmpty ? StructuredText.detect(text) ?? "text" : language.lowercased() }
    private var markdown:Bool { allowPreview && ["markdown","md","mkdown","mkd"].contains(lang) }
    private var formatted:String? { lang == "json" ? StructuredText.formatJSON(text) : nil }
    private var display:String { pretty ? formatted ?? text : text }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:12) {
                Text(lang.uppercased()).font(.system(size:10,design:.monospaced));Spacer(minLength:4)
                if markdown { Button(source ? "预览" : "源码") { source.toggle() } }
                else if formatted != nil { Button(pretty ? "源码" : "格式化") { pretty.toggle() } }
                Button("复制代码") { UIPasteboard.general.string=display }
            }.font(.caption).padding(.horizontal,12).padding(.vertical,8)
            Divider()
            if markdown && !source { AnyView(MarkdownText(text:text,previewMarkdownCode:false)).padding(12) }
            else { ScrollView(.horizontal) { Text(highlighted ?? AttributedString(display)).font(.system(size:13,design:.monospaced)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal:true,vertical:false).padding(12) } }
        }.background(ClientTheme.surface,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(ClientTheme.secondary.opacity(0.15),lineWidth:1)).padding(.vertical,4)
            .task(id: display) {
                let value = await CodeHighlightParser.shared.highlight(display)
                guard !Task.isCancelled else { return }
                highlighted = value
            }
    }
}

private struct MarkdownInlineText: View {
    let text: String
    @State private var parsed: AttributedString?
    var body: some View {
        Text(parsed ?? AttributedString(text))
            .task(id: text) {
                let value = await MarkdownInlineParser.shared.parse(text)
                guard !Task.isCancelled else { return }
                parsed = value
            }
    }
}

actor MarkdownInlineParser {
    static let shared = MarkdownInlineParser()
    private final class InlineEntry {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }
    private let inlineCache: NSCache<NSString, InlineEntry> = {
        let cache = NSCache<NSString, InlineEntry>(); cache.countLimit = 1000; cache.totalCostLimit = 2_000_000; return cache
    }()
    func parse(_ text: String) -> AttributedString {
        guard !Task.isCancelled else { return AttributedString() }
        if let cached = inlineCache.object(forKey: text as NSString) { return cached.value }
        let value = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        inlineCache.setObject(InlineEntry(value), forKey: text as NSString, cost: text.utf8.count * 2)
        return value
    }
}
