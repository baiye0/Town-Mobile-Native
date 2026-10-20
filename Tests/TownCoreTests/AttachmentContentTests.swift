import Foundation
import CryptoKit
import Testing
@testable import TownCore

private func contentGrant(_ data: Data) -> [String: Any] {
    ["attachment_id": "att_cross_device", "size": data.count,
     "checksum": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
     "download": ["method": "GET", "url": "https://test-bucket.oss-ap-northeast-1.aliyuncs.com/object?x-oss-signature=test", "headers": [:]]]
}

@Test func remoteAttachmentUsesGrantWithoutBeingCredentials() throws {
    let grant = try AttachmentContentGrant(contentGrant(Data("original bytes".utf8)), attachmentID: "att_cross_device")
    #expect(grant.request.url?.host == "test-bucket.oss-ap-northeast-1.aliyuncs.com")
    #expect(grant.request.httpMethod == "GET")
    #expect(grant.request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(grant.request.value(forHTTPHeaderField: "X-Being-Id") == nil)
    #expect(!grant.request.httpShouldHandleCookies)
}

@Test func originalFileMustMatchGrantSizeAndChecksum() throws {
    let bytes = Data("cross device original".utf8)
    let metadata = contentGrant(bytes)
    let grant = try AttachmentContentGrant(metadata, attachmentID: "att_cross_device")
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: path) }
    try bytes.write(to: path)
    try grant.verify(path)
    // The old implementation saved this JSON as the supposed original file.
    try JSONSerialization.data(withJSONObject: metadata).write(to: path)
    #expect(throws: (any Error).self) { try grant.verify(path) }
    try Data(repeating: 0, count: bytes.count).write(to: path)
    #expect(throws: (any Error).self) { try grant.verify(path) }
    try bytes.dropLast().write(to: path)
    #expect(throws: (any Error).self) { try grant.verify(path) }
}

@Test func malformedOrCredentialBearingDownloadGrantsAreRejected() throws {
    let valid = contentGrant(Data("ok".utf8))
    for url in ["http://test-bucket.oss-ap-northeast-1.aliyuncs.com/o", "https://evil.example/o", "https://test-bucket.oss-ap-northeast-1.aliyuncs.com.evil.example/o", "https://user:password@test-bucket.oss-ap-northeast-1.aliyuncs.com/o", "https://test-bucket.oss-ap-northeast-1.aliyuncs.com:8443/o"] {
        var changed = valid
        changed["download"] = ["method": "GET", "url": url, "headers": [:]]
        #expect(throws: (any Error).self) { try AttachmentContentGrant(changed, attachmentID: "att_cross_device") }
    }
    for (key, value) in [("size", AttachmentContentGrant.maximumSize + 1 as Any), ("attachment_id", "att_wrong" as Any), ("checksum", "invalid" as Any)] {
        var changed = valid; changed[key] = value
        #expect(throws: (any Error).self) { try AttachmentContentGrant(changed, attachmentID: "att_cross_device") }
    }
    var changed = valid
    var download = changed["download"] as! [String: Any]
    download["headers"] = ["Authorization": "Bearer must-not-leak"]
    changed["download"] = download
    #expect(throws: (any Error).self) { try AttachmentContentGrant(changed, attachmentID: "att_cross_device") }
}
