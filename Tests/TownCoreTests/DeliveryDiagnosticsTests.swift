import Foundation
import Testing
@testable import TownCore

@Test func attachmentFailureKeepsSpecificStageAndPosition() throws {
    let upload = DeliveryDiagnostics.step(AttachmentHTTPError(status: 403, code: "UPLOAD_DENIED"), stage: "上传附件文件")
    let batch = DeliveryDiagnostics.step(upload, stage: "上传附件", attachmentNumber: 2, attachmentCount: 3)
    let final = DeliveryDiagnostics.step(batch, stage: "准备消息").localizedDescription
    #expect(final.contains("上传附件文件失败（第 2/3 个附件）"))
    #expect(final.contains("HTTP 403") && final.contains("UPLOAD_DENIED"))
    #expect(!final.contains("准备消息"))
    var entry = PendingSend(endpoint: "https://example.invalid/being", sceneID: "s", title: "s", text: "private prompt")
    entry.phase = "failed"; entry.error = final
    let restored = try JSONDecoder().decode(PendingSend.self, from: JSONEncoder().encode(entry))
    #expect(DeliveryDiagnostics.detail(restored) == final)
}

@Test func failureReasonsDistinguishNetworkStatusAndLocalFiles() {
    #expect(DeliveryDiagnostics.reason(URLError(.timedOut)).contains("超时"))
    #expect(DeliveryDiagnostics.reason(URLError(.notConnectedToInternet)).contains("网络未连接"))
    #expect(DeliveryDiagnostics.reason(PortalError.http(401)).contains("凭据"))
    #expect(DeliveryDiagnostics.reason(PortalError.http(413)).contains("过大"))
    #expect(DeliveryDiagnostics.reason(PortalError.http(503)).contains("服务暂时不可用"))
    #expect(DeliveryDiagnostics.reason(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)).contains("重新选择"))
    #expect(DeliveryDiagnostics.reason(NSError(domain: NSCocoaErrorDomain, code: NSPropertyListReadCorruptError)).contains("数据格式无法解析"))
}

@Test func diagnosticsExcludeCredentialsResponseBodiesAndMessageContents() {
    let data = Data(#"{"error":{"code":"MEDIA_TIMEOUT","message":"Bearer private-token"},"url":"https://example.invalid/?token=secret"}"#.utf8)
    #expect(DeliveryDiagnostics.serviceCode(from: data) == "MEDIA_TIMEOUT")
    #expect(DeliveryDiagnostics.serviceCode("https://example.invalid/?token=secret") == nil)
    let raw = "HTTP 403 https://example.invalid/?token=secret Bearer abcdef token=xyz \"secret\":\"private\" file:///private/app/image.png"
    let clean = DeliveryDiagnostics.sanitized(raw)
    for secret in ["example.invalid", "abcdef", "xyz", "private", "image.png"] { #expect(!clean.contains(secret)) }
    #expect(clean.contains("HTTP 403"))
    var entry = PendingSend(endpoint: "private-endpoint", sceneID: "private-scene", title: "private-title", text: "private-prompt")
    entry.error = raw
    entry.files = [PendingAttachment(name: "private-filename", mime: "image/png", path: "private-path", size: 123)]
    let report = DeliveryDiagnostics.report(entry, version: "0.1.0 (8)")
    #expect(!report.contains("private"))
    #expect(report.contains("0.1.0 (8)") && report.contains("image/png") && report.contains("123 字节"))
    let transport = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: raw])
    #expect(!DeliveryDiagnostics.reason(transport).contains("secret"))
}

@Test func legacyFailureWithoutDetailsDoesNotInventCause() {
    var entry = PendingSend(endpoint: "e", sceneID: "s", title: "s", text: "")
    entry.phase = "failed"
    #expect(DeliveryDiagnostics.detail(entry).contains("未记录具体原因"))
    entry.phase = "unknown"
    #expect(DeliveryDiagnostics.detail(entry).contains("无法确认"))
}
