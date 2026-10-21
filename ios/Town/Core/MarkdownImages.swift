import Foundation

public enum MarkdownImagePart: Equatable {
    case text(String)
    case image(alt: String, url: URL)
}

/// Extract complete inline images without interpreting code spans or escaped syntax.
/// Keep URL query strings intact: generated images often use signed URLs.
public enum MarkdownImages {
    public static func parse(_ source: String) -> [MarkdownImagePart] {
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
            guard cursor + 1 < chars.count, chars[cursor + 1] == "(" else { i += 1; continue }
            let alt = string((i + 2)..<cursor)
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
            guard cursor < chars.count, chars[cursor] == ")", let url = URL(string: rawURL),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  url.host?.isEmpty == false, url.user == nil, url.password == nil else { i += 1; continue }
            if start < i { parts.append(.text(string(start..<i))) }
            parts.append(.image(alt: unescape(alt), url: url))
            i = cursor + 1; start = i
        }
        if start < chars.count { parts.append(.text(string(start..<chars.count))) }
        return parts.isEmpty ? [.text(source)] : parts
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: ##"\\([!"#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~])"##, with: "$1", options: .regularExpression)
    }
}
