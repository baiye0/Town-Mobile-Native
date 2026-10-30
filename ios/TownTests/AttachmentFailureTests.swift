import XCTest
@testable import Town

@MainActor final class AttachmentFailureTests: XCTestCase {
    func testMissingPhotoIdentifiesLocalReadAndAttachmentPosition() async throws {
        let store = Store()
        let connection = try Connection("https://example.invalid/test?token=fixture")
        let missing = UUID().uuidString + ".png"
        var entry = PendingSend(endpoint: connection.endpoint, sceneID: "s", title: "s", text: "")
        // The first file is already uploaded; the second must fail locally
        // without making any network request or blaming the server.
        entry.files = [
            PendingAttachment(name: "first.png", mime: "image/png", path: "first.png", size: 1, attachmentID: "a_first"),
            PendingAttachment(name: "private-photo-name.png", mime: "image/png", path: missing, size: 1)
        ]
        do {
            _ = try await store.prepareFiles(&entry, connection: connection)
            XCTFail("A missing photo must fail before upload")
        } catch {
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("读取本地附件失败（第 2/2 个附件）"))
            XCTAssertTrue(description.contains("重新选择"))
            XCTAssertFalse(description.contains(missing))
            XCTAssertFalse(description.contains("private-photo-name"))
            XCTAssertFalse(description.contains("HTTP"))
        }
    }
}
