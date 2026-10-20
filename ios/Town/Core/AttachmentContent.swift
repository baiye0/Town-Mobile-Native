import Foundation
import CryptoKit

/// The Gateway's /content response is a grant, never the original file bytes.
struct AttachmentContentGrant: Sendable {
    static let maximumSize = 50 * 1024 * 1024
    let size: Int
    let checksum: String
    let request: URLRequest

    init(_ metadata: [String: Any], attachmentID: String) throws {
        guard metadata["attachment_id"] as? String == attachmentID,
              let size = metadata["size"] as? Int, size >= 0, size <= Self.maximumSize,
              let checksum = metadata["checksum"] as? String,
              checksum.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let grant = metadata["download"] as? [String: Any], grant["method"] as? String == "GET",
              let raw = grant["url"] as? String, let url = URL(string: raw),
              url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443,
              let host = url.host,
              host.range(of: "^[a-z0-9-]+\\.oss-[a-z0-9-]+\\.aliyuncs\\.com$", options: .regularExpression) != nil,
              let headers = grant["headers"] as? [String: String] else { throw PortalError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        for (key, value) in headers {
            guard key.lowercased().range(of: "^(content-type|content-md5|content-length|x-oss-[a-z0-9-]+)$", options: .regularExpression) != nil,
                  !value.contains("\r"), !value.contains("\n") else { throw PortalError.invalidResponse }
            request.setValue(value, forHTTPHeaderField: key)
        }
        self.size = size; self.checksum = checksum; self.request = request
    }

    func verify(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256(), count = 0
        while let data = try handle.read(upToCount: 65536), !data.isEmpty {
            try Task.checkCancellation()
            count += data.count
            guard count <= size else { throw PortalError.server("附件大小校验失败，请重新下载。") }
            hash.update(data: data)
        }
        guard count == size, hash.finalize().map({ String(format: "%02x", $0) }).joined() == checksum else {
            throw PortalError.server("附件完整性校验失败，请重新下载。")
        }
    }
}
