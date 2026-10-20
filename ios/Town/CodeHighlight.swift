import SwiftUI
func highlightedCode(_ source: String) -> AttributedString {
    var result = AttributedString(source)
    guard source.utf8.count <= 100000 else { return result }
    let pattern = #"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|//[^\n]*|#[^\n]*|\b(?:true|false|null|nil|None|True|False|func|fun|function|class|struct|enum|import|from|return|if|else|for|while|let|var|val|const|async|await|try|catch|throw|public|private|def|in)\b|\b\d+(?:\.\d+)?\b"#
    guard let regex = try? NSRegularExpression(pattern:pattern) else { return result }
    for match in regex.matches(in:source,range:NSRange(source.startIndex...,in:source)) {
        guard let range = Range(match.range,in:source), let attributed = Range(range,in:result) else { continue }
        let value = source[range]
        result[attributed].foregroundColor = value.hasPrefix("\"") || value.hasPrefix("'") ? .green : value.hasPrefix("//") || value.hasPrefix("#") ? .secondary : value.first?.isNumber == true ? .orange : .purple
    }
    return result
}
