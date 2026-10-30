import Foundation
public struct MarkdownBlock: Equatable, Sendable {
    public enum Kind: Sendable { case paragraph, heading, code, quote, list, rule, table, image }
    public var kind: Kind
    public var text: String
    public var level: Int = 0
    public var label: String = ""
    public var rows: [[String]] = []
}
public enum MarkdownBlocks {
    private static let patterns: [String: NSRegularExpression] = Dictionary(uniqueKeysWithValues: [
        "^\\s*\\|?\\s*:?-{3,}:?\\s*(\\|\\s*:?-{3,}:?\\s*)+\\|?\\s*$",
        "^(#{1,6})\\s+(.+)$",
        "^(?:[-*_]\\s*){3,}$",
        "^(\\s*)([-+*]|[0-9]+[.)])\\s+(.+)$"
    ].map { ($0, try! NSRegularExpression(pattern: $0)) })
    private static func match(_ pattern: String, _ line: String) -> [String]? {
        guard let regex = patterns[pattern], let m = regex.firstMatch(in:line,range:NSRange(line.startIndex...,in:line)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at:$0),in:line).map { String(line[$0]) } ?? "" }
    }
    private static func cells(_ line: String) -> [String] {
        var result:[String] = [], cell = "", escaped = false, code = false
        for char in line.trimmingCharacters(in:.whitespaces) {
            if escaped { cell.append(char); escaped = false; continue }
            if char == "\\" { escaped = true; continue }
            if char == "`" { code.toggle() }
            if char == "|" && !code { result.append(cell.trimmingCharacters(in:.whitespaces)); cell = "" } else { cell.append(char) }
        }
        result.append(cell.trimmingCharacters(in:.whitespaces))
        if result.first == "" { result.removeFirst() }; if result.last == "" { result.removeLast() }
        return result
    }
    public static func parse(_ text: String, imageReferences: String = "") -> [MarkdownBlock] {
        if let language = StructuredText.detect(text) { return [MarkdownBlock(kind:.code,text:text,label:language)] }
        let lines = text.replacingOccurrences(of:"\r\n",with:"\n").components(separatedBy:"\n")
        var blocks:[MarkdownBlock] = [], paragraph:[String] = [], i = 0
        func flush() { if !paragraph.isEmpty { blocks.append(MarkdownBlock(kind:.paragraph,text:paragraph.joined(separator:"\n"))); paragraph=[] } }
        while i < lines.count {
            let line=lines[i], trimmed=line.trimmingCharacters(in:.whitespaces)
            if trimmed.isEmpty { flush(); i += 1; continue }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush(); let fence=String(trimmed.prefix(3)), language=String(trimmed.dropFirst(3)); i += 1; var code:[String]=[]
                while i < lines.count && !lines[i].trimmingCharacters(in:.whitespaces).hasPrefix(fence) { code.append(lines[i]); i += 1 }
                blocks.append(MarkdownBlock(kind:.code,text:code.joined(separator:"\n"),label:language)); i += 1; continue
            }
            if i+1 < lines.count, line.contains("|"), match("^\\s*\\|?\\s*:?-{3,}:?\\s*(\\|\\s*:?-{3,}:?\\s*)+\\|?\\s*$",lines[i+1]) != nil {
                flush();var rows=[cells(line)];i += 2
                while i < lines.count && lines[i].contains("|") && !lines[i].trimmingCharacters(in:.whitespaces).isEmpty { rows.append(cells(lines[i]));i += 1 }
                blocks.append(MarkdownBlock(kind:.table,text:"",rows:rows));continue
            }
            if let heading=match("^(#{1,6})\\s+(.+)$",trimmed) { flush();blocks.append(MarkdownBlock(kind:.heading,text:heading[2],level:heading[1].count));i += 1;continue }
            if match("^(?:[-*_]\\s*){3,}$",trimmed) != nil { flush();blocks.append(MarkdownBlock(kind:.rule,text:""));i += 1;continue }
            if trimmed.hasPrefix(">") { flush();blocks.append(MarkdownBlock(kind:.quote,text:String(trimmed.dropFirst()).trimmingCharacters(in:.whitespaces)));i += 1;continue }
            if let list=match("^(\\s*)([-+*]|[0-9]+[.)])\\s+(.+)$",line) {
                flush();var label=list[2].count==1 ? "•" : list[2], content=list[3]
                if content.hasPrefix("[ ] ") { label="☐";content=String(content.dropFirst(4)) }
                if content.lowercased().hasPrefix("[x] ") { label="☑";content=String(content.dropFirst(4)) }
                blocks.append(MarkdownBlock(kind:.list,text:content,level:list[1].count/2,label:label));i += 1;continue
            }
            paragraph.append(line);i += 1
        }
        flush();return MarkdownImages.expand(blocks, definitions: imageReferences)
    }
}
