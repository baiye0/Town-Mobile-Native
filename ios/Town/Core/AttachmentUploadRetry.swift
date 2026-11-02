import Foundation

enum AttachmentUploadRetry {
    // Only for PUT of the same immutable file to the same reserved object.
    // Never apply this to message creation or chat POSTs with an unknown outcome.
    static func run(
        operation: @Sendable () async throws -> Void,
        onRetry: @Sendable (Int) async -> Void = { _ in },
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                try await operation()
                try Task.checkCancellation()
                return
            } catch {
                try Task.checkCancellation()
                let failure = error as NSError
                let transient = failure.domain == NSURLErrorDomain &&
                    [NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut].contains(failure.code)
                guard transient, attempt < 2 else {
                    if error is CancellationError || (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) {
                        throw error
                    }
                    guard attempt > 0 else { throw error }
                    throw DeliveryStepError(stage: "上传附件文件", reason: DeliveryDiagnostics.reason(error) + "\n已自动重试 \(attempt) 次，仍未完成上传。")
                }
                await onRetry(attempt + 1)
                try Task.checkCancellation()
                try await sleep(.seconds(attempt == 0 ? 1 : 3))
            }
        }
    }
}
