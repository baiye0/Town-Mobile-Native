import Foundation

public enum MarkdownImagePart: Equatable {
    case text(String)
    case image(alt: String, url: URL)
}

/// Extract complete inline images without interpreting code spans or escaped syntax.
/// Keep URL query strings intact: generated images often use signed URLs.
public enum MarkdownImages {
    static func definitions(_ text: String) -> String {
        var fence: String?
        return text.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let mark = fence {
                if trimmed.count >= mark.count && trimmed.allSatisfy({ $0 == mark.first! }) { fence = nil }
                return false
            }
            if let range = trimmed.range(of: #"^(`{3,}|~{3,})"#, options: .regularExpression) { fence = String(trimmed[range]); return false }
            return line.range(of: #"^ {0,3}\[([^\]]+)\]:\s*<?(\S+?)>?(?:\s+"[^"]*")?\s*$"#, options: .regularExpression) != nil
        }.joined(separator: "\n")
    }
    static func expand(_ blocks: [MarkdownBlock], definitions: String = "") -> [MarkdownBlock] {
        let definition = try! NSRegularExpression(pattern: #"^ {0,3}\[([^\]]+)\]:\s*<?(\S+?)>?(?:\s+"[^"]*")?\s*$"#)
        func captures(_ text: String) -> [String]? {
            guard let m = definition.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
        var refs: [String: String] = [:]
        for block in [MarkdownBlock(kind: .paragraph, text: definitions)] + blocks where block.kind == .paragraph {
            for line in block.text.components(separatedBy: "\n") {
                if let c = captures(line), refs[c[1].lowercased()] == nil { refs[c[1].lowercased()] = c[2] }
            }
        }
        return blocks.flatMap { block -> [MarkdownBlock] in
            guard [.paragraph, .heading, .quote, .list].contains(block.kind) else { return [block] }
            let text = block.text.components(separatedBy: "\n").filter { captures($0) == nil }.joined(separator: "\n")
            return parse(text, references: refs, allowData: true).compactMap { part -> MarkdownBlock? in
                switch part {
                case .text(let value):
                    guard !value.isEmpty else { return nil }
                    var result = block; result.text = value; return result
                case .image(let alt, let url): return MarkdownBlock(kind: .image, text: url.absoluteString, label: alt)
                }
            }
        }
    }
    public static func parse(_ source: String) -> [MarkdownImagePart] {
        parse(source, references: [:], allowData: false)
    }

    private static func parse(_ source: String, references: [String: String], allowData: Bool) -> [MarkdownImagePart] {
        let chars = Array(source)
        var parts: [MarkdownImagePart] = [], start = 0, i = 0
        func escaped(_ index: Int) -> Bool {
            var cursor = index, count = 0
            while cursor > 0 && chars[cursor - 1] == "\\" { count += 1; cursor -= 1 }
            return count % 2 == 1
        }
        func string(_ range: Range<Int>) -> String { String(chars[range]) }
        while i < chars.count {
            if chars[i] == "`", !escaped(i) {
                var end = i
                while end < chars.count && chars[end] == "`" { end += 1 }
                let run = end - i
                var cursor = end, closing: Int?
                while cursor < chars.count {
                    if chars[cursor] == "`" {
                        var next = cursor
                        while next < chars.count && chars[next] == "`" { next += 1 }
                        if next - cursor == run { closing = next; break }
                        cursor = next
                    } else { cursor += 1 }
                }
                i = closing ?? chars.count
                continue
            }
            guard chars[i] == "!", !escaped(i), i + 1 < chars.count, chars[i + 1] == "[" else { i += 1; continue }
            var cursor = i + 2, depth = 1
            while cursor < chars.count {
                if !escaped(cursor) {
                    if chars[cursor] == "[" { depth += 1 }
                    if chars[cursor] == "]" { depth -= 1; if depth == 0 { break } }
                }
                cursor += 1
            }
            guard cursor + 1 < chars.count else { i += 1; continue }
            let alt = string((i + 2)..<cursor)
            if chars[cursor + 1] == "[" {
                let keyStart = cursor + 2
                var end = keyStart
                while end < chars.count && (chars[end] != "]" || escaped(end)) { end += 1 }
                guard end < chars.count else { i += 1; continue }
                let key = string(keyStart..<end)
                guard let raw = references[(key.isEmpty ? alt : key).lowercased()], let url = imageURL(raw, allowData: allowData) else { i += 1; continue }
                if start < i { parts.append(.text(string(start..<i))) }
                parts.append(.image(alt: unescape(alt), url: url))
                i = end + 1; start = i; continue
            }
            guard chars[cursor + 1] == "(" else { i += 1; continue }
            cursor += 2
            while cursor < chars.count && chars[cursor].isWhitespace { cursor += 1 }
            let angle = cursor < chars.count && chars[cursor] == "<"
            if angle { cursor += 1 }
            let urlStart = cursor
            depth = 0
            while cursor < chars.count {
                let ch = chars[cursor]
                if !escaped(cursor) {
                    if angle && ch == ">" { break }
                    if !angle {
                        if ch == "(" { depth += 1 }
                        if ch == ")" { if depth == 0 { break }; depth -= 1 }
                        if ch.isWhitespace && depth == 0 { break }
                    }
                }
                cursor += 1
            }
            let rawURL = unescape(string(urlStart..<cursor))
            if angle {
                guard cursor < chars.count && chars[cursor] == ">" else { i += 1; continue }
                cursor += 1
            }
            let whitespaceStart = cursor
            while cursor < chars.count && chars[cursor].isWhitespace { cursor += 1 }
            // Optional Markdown title, separated from the destination by whitespace.
            if cursor > whitespaceStart, cursor < chars.count, ["\"", "'", "("].contains(chars[cursor]) {
                let terminator: Character = chars[cursor] == "(" ? ")" : chars[cursor]
                cursor += 1
                while cursor < chars.count && (chars[cursor] != terminator || escaped(cursor)) { cursor += 1 }
                guard cursor < chars.count else { i += 1; continue }
                cursor += 1
                while cursor < chars.count && chars[cursor].isWhitespace { cursor += 1 }
            }
            guard cursor < chars.count, chars[cursor] == ")", let url = imageURL(rawURL, allowData: allowData) else { i += 1; continue }
            if start < i { parts.append(.text(string(start..<i))) }
            parts.append(.image(alt: unescape(alt), url: url))
            i = cursor + 1; start = i
        }
        if start < chars.count { parts.append(.text(string(start..<chars.count))) }
        return parts.isEmpty ? [.text(source)] : parts
    }

    private static func imageURL(_ raw: String, allowData: Bool) -> URL? {
        guard let url = URL(string: raw) else { return nil }
        if allowData, raw.hasPrefix("data:image/"), raw.range(of: #"^data:image/(png|jpeg|gif|webp|avif);base64,[A-Za-z0-9+/=]+$"#, options: .regularExpression) != nil { return url }
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: ##"\\([!"#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~])"##, with: "$1", options: .regularExpression)
    }
}
