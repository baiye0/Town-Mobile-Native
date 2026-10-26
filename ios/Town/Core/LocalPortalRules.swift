import Foundation
import CryptoKit
import Darwin

public struct LocalPortalOptions: Codable, Equatable, Sendable {
    public var name = "ios-" + String(UUID().uuidString.prefix(8)).lowercased()
    public var files = true
    public var grants: Set<String> = []
    public init() {}
    public func validate() throws {
        guard name.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil else {
            throw PortalError.server("设备名需为 1–64 位字母、数字、横线或下划线。")
        }
    }
}

public enum LocalPortalRules {
    public static let maxFileSize = 10 * 1024 * 1024
    public static func owner(_ connection: Connection) -> String {
        SHA256.hash(data: Data(connection.endpoint.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static func relayURL(_ connection: Connection) throws -> URL {
        guard var url = URLComponents(string: connection.endpoint) else { throw PortalError.invalidLink }
        url.scheme = url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "") ? "ws" : "wss"
        url.path = "/_relay"; url.query = nil; url.fragment = nil
        guard let result = url.url else { throw PortalError.invalidLink }; return result
    }
    public static func fingerprint(tool: String, arguments: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["tool": tool, "arguments": arguments], options: [.sortedKeys])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func string(_ args: [String: Any], _ key: String, max: Int = 4096) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty, value.utf8.count <= max else {
            throw PortalError.server("参数 \(key) 缺失或过长。")
        }; return value
    }
    public static func date(_ args: [String: Any], _ key: String) throws -> Date {
        let value = try string(args, key, max: 64)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) else {
            throw PortalError.server("\(key) 需为含时区的 ISO 8601 时间。")
        }; return date
    }
}

/// No tool creates symlinks. Reject every symlink component, including dangling links.
/// This workspace never contains the app's credentials, chat cache or permission records.
public struct LocalPortalWorkspace: Sendable {
    public let root: URL
    public init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Foundation intentionally aliases /private/var to /var, while directory
        // enumeration returns the physical path. Keep one physical root for both.
        guard let canonical = realpath(root.path, nil) else { throw PortalError.server("工作区路径不可用。") }
        defer { free(canonical) }
        self.root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
    }
    public func resolve(_ path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"), path.utf8.count <= 2048 else {
            throw PortalError.server("仅可访问 Portal 工作区内的相对路径。")
        }
        var url = root
        for part in path.split(separator: "/") {
            guard part != ".." else { throw PortalError.server("路径超出 Portal 工作区。") }
            if part == "." { continue }
            url.appendPathComponent(String(part))
            if let type = try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType,
               type == .typeSymbolicLink { throw PortalError.server("工作区不允许访问符号链接。") }
        }
        return url
    }
    public func read(_ path: String) throws -> Data {
        let url = try resolve(path)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= LocalPortalRules.maxFileSize else {
            throw PortalError.server("仅支持不超过 10 MB 的普通文件。")
        }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: LocalPortalRules.maxFileSize + 1) ?? Data()
        guard data.count <= LocalPortalRules.maxFileSize else { throw PortalError.server("文件超过 10 MB。") }
        return data
    }
    public func write(_ path: String, data: Data, overwrite: Bool = true) throws {
        guard data.count <= LocalPortalRules.maxFileSize else { throw PortalError.server("文件超过 10 MB。") }
        let url = try resolve(path)
        guard url != root else { throw PortalError.server("请选择文件路径。") }
        if !overwrite && FileManager.default.fileExists(atPath: url.path) { throw PortalError.server("同名文件已存在。") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: overwrite ? [.atomic] : [.withoutOverwriting])
    }
    public func list(_ path: String = ".") throws -> [[String: Any]] {
        let directory = try resolve(path)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(500).compactMap { url in
                let relative = String(url.path.dropFirst(root.path.count + 1))
                guard (try? resolve(relative)) != nil, let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { return nil }
                return ["name": url.lastPathComponent, "path": relative, "is_dir": values.isDirectory == true, "size": values.fileSize ?? 0]
            }
    }
    public func search(_ pattern: String, path: String, limit: Int) throws -> [[String: Any]] {
        try Task.checkCancellation()
        // Literal search is bounded and avoids backtracking regex on untrusted patterns.
        guard !pattern.isEmpty, pattern.count <= 1024 else { throw PortalError.server("搜索文字需为 1–1024 个字符。") }
        let base = try resolve(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDir) else { throw PortalError.server("搜索路径不存在。") }
        let enumerator = isDir.boolValue ? FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) : nil
        var candidates = [URL]()
        if !isDir.boolValue { candidates = [base] }
        while let url = enumerator?.nextObject() as? URL, candidates.count < 2000 {
            try Task.checkCancellation()
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { enumerator?.skipDescendants(); continue }
            candidates.append(url)
        }
        var matches = [[String: Any]](), budget = 20 * 1024 * 1024
        for url in candidates {
            try Task.checkCancellation()
            let relative = String(url.path.dropFirst(root.path.count + 1))
            guard let data = try? read(relative) else { continue }
            budget -= data.count; if budget < 0 { break }
            guard let text = String(data: data, encoding: .utf8) else { continue }
            for (line, text) in text.components(separatedBy: "\n").enumerated() where text.localizedCaseInsensitiveContains(pattern) {
                try Task.checkCancellation()
                matches.append(["path": relative, "line": line + 1, "text": String(text.prefix(1000))])
                if matches.count >= max(1, min(limit, 200)) { return matches }
            }
        }
        return matches
    }
}
