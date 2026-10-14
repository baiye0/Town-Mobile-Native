import SwiftUI
struct MarkdownText: View {
    let text: String
    var previewMarkdownCode = true
    var foreground:Color? = nil
    var fillsWidth = true
    private func inline(_ text:String) -> Text { Text((try? AttributedString(markdown:text,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(text)) }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            ForEach(Array(MarkdownRenderCache.blocks(text).enumerated()),id:\.offset) { _,block in
                switch block.kind {
                case .paragraph: inline(block.text).font(.system(size:16)).lineSpacing(7).textSelection(.enabled)
                case .heading: inline(block.text).font(.system(size:block.level == 1 ? 20 : block.level == 2 ? 18 : 16,weight:.semibold)).padding(.top,8).textSelection(.enabled)
                case .list:
                    HStack(alignment:.top,spacing:8) { Text(block.label).frame(minWidth:18,alignment:.trailing); inline(block.text).frame(maxWidth:.infinity,alignment:.leading) }.font(.system(size:16)).lineSpacing(6).padding(.leading,CGFloat(min(block.level,8))*16).textSelection(.enabled)
                case .quote:
                    HStack(alignment:.top,spacing:12) { Rectangle().fill(ClientTheme.secondary.opacity(0.3)).frame(width:3);inline(block.text).font(.system(size:16)).lineSpacing(6).foregroundStyle(foreground ?? ClientTheme.secondary) }.fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                case .rule: Divider().padding(.vertical,8)
                case .code:
                    NativeCodeBlock(text:block.text,language:block.label,allowPreview:previewMarkdownCode).foregroundStyle(ClientTheme.text)
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
        }.foregroundStyle(foreground ?? ClientTheme.text).frame(maxWidth:fillsWidth ? .infinity : nil,alignment:.leading)
            .environment(\.openURL,OpenURLAction { url in ["https","http"].contains(url.scheme ?? "") && url.user == nil && url.password == nil ? .systemAction : .discarded })
    }
}

struct NativeCodeBlock: View {
    let text:String
    let language:String
    let allowPreview:Bool
    @State private var source=false
    @State private var pretty=false
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
            else { ScrollView(.horizontal) { Text(display).font(.system(size:13,design:.monospaced)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal:true,vertical:false).padding(12) } }
        }.background(ClientTheme.surface,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(ClientTheme.secondary.opacity(0.15),lineWidth:1)).padding(.vertical,4)
    }
}

@MainActor private enum MarkdownRenderCache {
    private final class Entry { let blocks: [MarkdownBlock]; init(_ blocks: [MarkdownBlock]) { self.blocks = blocks } }
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>(); cache.countLimit = 200; cache.totalCostLimit = 2_000_000; return cache
    }()
    static func blocks(_ text: String) -> [MarkdownBlock] {
        if let entry = cache.object(forKey: text as NSString) { return entry.blocks }
        let blocks = MarkdownBlocks.parse(text)
        cache.setObject(Entry(blocks), forKey: text as NSString, cost: text.utf8.count * 2)
        return blocks
    }
}
