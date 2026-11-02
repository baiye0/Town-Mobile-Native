import Foundation
import Testing
@testable import TownCore

private actor UploadAttempts {
    var calls = 0
    var retries: [Int] = []
    var delays: [Duration] = []
    func next() -> Int { calls += 1; return calls }
    func retry(_ value: Int) { retries.append(value) }
    func delay(_ value: Duration) { delays.append(value) }
}

@Test func uploadRecoversFromLostConnectionAndTimeout() async throws {
    let attempts = UploadAttempts()
    try await AttachmentUploadRetry.run(operation: {
        switch await attempts.next() {
        case 1: throw URLError(.networkConnectionLost)
        case 2: throw URLError(.timedOut)
        default: return
        }
    }, onRetry: { await attempts.retry($0) }, sleep: { await attempts.delay($0) })
    #expect(await attempts.calls == 3)
    #expect(await attempts.retries == [1, 2])
    #expect(await attempts.delays == [.seconds(1), .seconds(3)])
}

@Test func uploadStopsAfterThreeAttemptsAndPreservesDiagnostics() async {
    let attempts = UploadAttempts()
    do {
        try await AttachmentUploadRetry.run(operation: {
            _ = await attempts.next()
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost,
                          userInfo: [NSLocalizedDescriptionKey: "https://secret.invalid/?token=private"])
        }, sleep: { _ in })
        Issue.record("Upload should fail after bounded retries")
    } catch {
        let detail = DeliveryDiagnostics.step(error, stage: "上传附件", attachmentNumber: 1, attachmentCount: 1).localizedDescription
        #expect(detail.contains("上传附件文件失败（第 1/1 个附件）"))
        #expect(detail.contains("-1005") && detail.contains("已自动重试 2 次"))
        #expect(!detail.contains("secret") && !detail.contains("private"))
    }
    #expect(await attempts.calls == 3)
}

@Test func uploadDoesNotRetryHTTPRejectionsLocalErrorsOrCancellation() async {
    let errors: [any Error] = [AttachmentHTTPError(status: 403), AttachmentHTTPError(status: 413),
                               AttachmentHTTPError(status: 500), CocoaError(.fileReadNoSuchFile),
                               URLError(.serverCertificateUntrusted), URLError(.cancelled), CancellationError()]
    for expected in errors {
        let attempts = UploadAttempts()
        do {
            try await AttachmentUploadRetry.run(operation: {
                _ = await attempts.next(); throw expected
            }, sleep: { _ in Issue.record("Non-transient error must not back off") })
            Issue.record("Expected the original failure")
        } catch {
            #expect((error as NSError).domain == (expected as NSError).domain)
            #expect((error as NSError).code == (expected as NSError).code)
        }
        #expect(await attempts.calls == 1)
    }
}

@Test func cancelledUploadDoesNotRetryAfterBackoffBegins() async {
    let attempts = UploadAttempts()
    let task = Task {
        try await AttachmentUploadRetry.run(operation: {
            _ = await attempts.next(); throw URLError(.networkConnectionLost)
        }, sleep: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            try Task.checkCancellation()
        })
    }
    do { try await task.value; Issue.record("Expected cancellation") }
    catch { #expect(error is CancellationError) }
    #expect(await attempts.calls == 1)
}

@Test func successfulUploadDoesNotRepeat() async throws {
    let attempts = UploadAttempts()
    try await AttachmentUploadRetry.run(operation: { _ = await attempts.next() },
                                        sleep: { _ in Issue.record("Successful upload must not retry") })
    #expect(await attempts.calls == 1)
}

@Test func uploadReportsLastRejectionAndActualRetryCount() async {
    let attempts = UploadAttempts()
    do {
        try await AttachmentUploadRetry.run(operation: {
            if await attempts.next() == 1 { throw URLError(.networkConnectionLost) }
            throw AttachmentHTTPError(status: 403)
        }, sleep: { await attempts.delay($0) })
        Issue.record("A rejected PUT must stop retrying")
    } catch {
        #expect(error.localizedDescription.contains("HTTP 403"))
        #expect(error.localizedDescription.contains("已自动重试 1 次"))
    }
    #expect(await attempts.calls == 2)
    #expect(await attempts.delays == [.seconds(1)])
}
