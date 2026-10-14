import Foundation

public enum PortalError: Error, LocalizedError {
    case invalidLink, http(Int), invalidResponse, server(String)
    public var errorDescription: String? {
        switch self {
        case .invalidLink: return "请输入有效的 HTTPS Being 链接，包含 token。"
        case .http(let code): return "连接失败（HTTP \(code)），请检查地址和凭据。"
        case .invalidResponse: return "服务返回了无法识别的数据。"
        case .server(let text): return text
        }
    }
}
public struct Connection: Codable, Equatable, Sendable {
    public let endpoint: String
    public let being: String
    public let token: String
    public let secret: String
    public init(_ text: String) throws {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.scheme == "https" || (c.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)),
              c.path.range(of: "^/[a-zA-Z0-9_-]+/?$", options: .regularExpression) != nil,
              let token = c.queryItems?.first(where: { $0.name == "token" })?.value,
              token.range(of: "^[a-zA-Z0-9._~-]{1,2048}$", options: .regularExpression) != nil else { throw PortalError.invalidLink }
        being = c.path.replacingOccurrences(of: "/", with: "")
        var origin = c; origin.path = "/" + being; origin.query = nil; origin.fragment = nil
        guard let endpoint = origin.url?.absoluteString else { throw PortalError.invalidLink }
        self.endpoint = endpoint; self.token = token
        secret = c.queryItems?.first(where: { ["relay_secret", "secret"].contains($0.name) })?.value ?? token
        guard !secret.contains("\r"), !secret.contains("\n") else { throw PortalError.invalidLink }
    }
    public func url(_ path: String) -> URL {
        var c = URLComponents(string: endpoint + path)!
        c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "token", value: token)]
        return c.url!
    }
}
public struct SSEEvent: Equatable, Sendable { public let name: String; public let data: String }
public struct SSEParser {
    private var name = "message"
    private var data: [String] = []
    public init() {}
    public mutating func line(_ raw: String) -> SSEEvent? {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if line.isEmpty {
            defer { name = "message"; data = [] }
            return data.isEmpty ? nil : SSEEvent(name: name, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        if parts[0] == "event" { name = value }
        if parts[0] == "data" { data.append(value) }
        return nil
    }
}
struct Message: Codable, Identifiable { var id = UUID(); var role: String; var text: String; var sceneID: String? = nil; var sequence: Int? = nil; var kind: String? = nil; var timestamp: String? = nil; var sceneLabel: String? = nil }
struct Conversation: Codable, Identifiable {
    var id: String = "mobile-" + UUID().uuidString
    var endpoint: String; var title = "新对话"; var messages: [Message] = []; var updated = Date()
}

/// URLSession.AsyncBytes.lines drops empty lines, which are SSE frame boundaries.
/// Decode raw bytes instead; UTF-8 is decoded only after a complete line arrives.
public struct SSEByteParser {
    private var line: [UInt8] = []
    private var lastWasCR = false
    private var parser = SSEParser()
    public init() {}
    public mutating func consume(_ byte: UInt8) throws -> SSEEvent? {
        if byte == 10 && lastWasCR { lastWasCR = false; return nil }
        if byte == 10 || byte == 13 {
            lastWasCR = byte == 13
            let value = String(decoding: line, as: UTF8.self); line.removeAll(keepingCapacity: true)
            return parser.line(value)
        }
        lastWasCR = false
        guard line.count < 1024 * 1024 else { throw PortalError.invalidResponse }
        line.append(byte); return nil
    }
    public mutating func finish() -> SSEEvent? {
        if !line.isEmpty { _ = parser.line(String(decoding:line,as:UTF8.self)); line.removeAll() }
        return parser.line("")
    }
}
