import Foundation

enum MarkdownImages {
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
        let pattern = try! NSRegularExpression(pattern: #"`+[^`]*`+|!\[([^\]]*)\](?:\(<?((?:[^\s<>()]|\([^\s<>()]*\))+)>?(?:\s+"[^"]*")?\)|\[([^\]]*)\])"#)
        let definition = try! NSRegularExpression(pattern: #"^ {0,3}\[([^\]]+)\]:\s*<?(\S+?)>?(?:\s+"[^"]*")?\s*$"#)
        func captures(_ regex: NSRegularExpression, _ text: String) -> [String]? {
            guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
        var refs: [String: String] = [:]
        for block in [MarkdownBlock(kind: .paragraph, text: definitions)] + blocks where block.kind == .paragraph {
            for line in block.text.components(separatedBy: "\n") {
                if let c = captures(definition, line), refs[c[1].lowercased()] == nil { refs[c[1].lowercased()] = c[2] }
            }
        }
        return blocks.flatMap { block -> [MarkdownBlock] in
            guard [.paragraph, .heading, .quote, .list].contains(block.kind) else { return [block] }
            let text = block.text.components(separatedBy: "\n").filter { captures(definition, $0) == nil }.joined(separator: "\n")
            var result: [MarkdownBlock] = [], start = text.startIndex
            for m in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(m.range, in: text), text[range].hasPrefix("!"),
                      range.lowerBound == text.startIndex || text[text.index(before: range.lowerBound)] != "\\" else { continue }
                let alt = Range(m.range(at: 1), in: text).map { String(text[$0]) } ?? ""
                let key = Range(m.range(at: 3), in: text).map { String(text[$0]) } ?? ""
                guard let url = Range(m.range(at: 2), in: text).map({ String(text[$0]) }) ?? refs[(key.isEmpty ? alt : key).lowercased()] else { continue }
                if start < range.lowerBound { var part = block; part.text = String(text[start..<range.lowerBound]); result.append(part) }
                result.append(MarkdownBlock(kind: .image, text: url, label: alt)); start = range.upperBound
            }
            if start < text.endIndex { var part = block; part.text = String(text[start...]); result.append(part) }
            return result
        }
    }
}
