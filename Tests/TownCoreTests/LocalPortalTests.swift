import Foundation
import Testing
@testable import TownCore

@Test func cancelledPortalSearchDoesNotContinueScanning() async throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temp) }
    let workspace = try LocalPortalWorkspace(root: temp)
    try workspace.write("large.txt", data: Data(String(repeating: "searchable line\n", count: 100000).utf8))
    let operation = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        _ = try workspace.search("searchable", path: ".", limit: 200)
    }
    do { _ = try await operation.value; Issue.record("Cancelled search returned results") }
    catch is CancellationError {}
}

@Test func localPortalRelayUsesOriginAndNeverTokenInURL() throws {
    let connection = try Connection("https://example.com:8443/alice?token=secret&relay_secret=other")
    #expect(try LocalPortalRules.relayURL(connection).absoluteString == "wss://example.com:8443/_relay")
    #expect(try LocalPortalRules.relayURL(Connection("http://127.0.0.1:1234/alice?token=test")).absoluteString == "ws://127.0.0.1:1234/_relay")
    #expect(LocalPortalRules.owner(connection) == LocalPortalRules.owner(try Connection("https://example.com:8443/alice?token=rotated")))
    #expect(LocalPortalRules.owner(connection) != LocalPortalRules.owner(try Connection("https://example.com:8443/bob?token=secret")))
}

@Test func localPortalRejectsTraversalAndSymlinkParents() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temp) }
    let workspace = try LocalPortalWorkspace(root: temp.appendingPathComponent("workspace"))
    let outside = temp.appendingPathComponent("private"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data("secret".utf8).write(to: outside.appendingPathComponent("credentials"))
    for path in ["../private/credentials", "/etc/passwd", "sub/../../private", "bad\\name", "bad\0name"] {
        #expect(throws: (any Error).self) { try workspace.read(path) }
        #expect(throws: (any Error).self) { try workspace.write(path, data: Data()) }
    }
    try FileManager.default.createSymbolicLink(at: workspace.root.appendingPathComponent("escape"), withDestinationURL: outside)
    #expect(throws: (any Error).self) { try workspace.read("escape/credentials") }
    #expect(throws: (any Error).self) { try workspace.write("escape/new/file", data: Data()) }
    try FileManager.default.createSymbolicLink(at: workspace.root.appendingPathComponent("dangling"), withDestinationURL: outside.appendingPathComponent("absent"))
    #expect(throws: (any Error).self) { try workspace.write("dangling/file", data: Data()) }
    #expect(try workspace.list().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("new").path))
}

@Test func localPortalWorkspaceImportLimitsAndBoundedSearch() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temp) }
    let workspace = try LocalPortalWorkspace(root: temp)
    try workspace.write("nested/hello.txt", data: Data("Hello\n世界\nHELLO".utf8))
    #expect(try workspace.read("nested/hello.txt") == Data("Hello\n世界\nHELLO".utf8))
    #expect(throws: (any Error).self) { try workspace.write("nested/hello.txt", data: Data(), overwrite: false) }
    #expect(throws: (any Error).self) { try workspace.write("too-large", data: Data(count: LocalPortalRules.maxFileSize + 1)) }
    #expect(throws: (any Error).self) { try workspace.write(".", data: Data()) }
    #expect(try workspace.search("hello", path: ".", limit: 1).count == 1)
    #expect(try workspace.search(".*", path: ".", limit: 10).isEmpty)
    #expect(try workspace.search("世界", path: ".", limit: 10).first?["line"] as? Int == 2)
    #expect(throws: (any Error).self) { try workspace.search("hello", path: "../", limit: 10) }
}

@Test func localPortalConfigurationAndRetryIdentity() throws {
    var options = LocalPortalOptions()
    #expect(options.files && options.grants.isEmpty)
    for name in ["", "a/b", "\ninvalid", String(repeating: "x", count: 65)] { options.name = name; #expect(throws: (any Error).self) { try options.validate() } }
    options.name = "ios-device_01"; try options.validate()
    let a = try LocalPortalRules.fingerprint(tool: "calendar", arguments: ["title": "one", "request_id": "id"])
    let b = try LocalPortalRules.fingerprint(tool: "calendar", arguments: ["request_id": "id", "title": "one"])
    #expect(a == b)
    #expect(a != (try LocalPortalRules.fingerprint(tool: "calendar", arguments: ["title": "two", "request_id": "id"])))
    #expect(throws: (any Error).self) { try LocalPortalRules.date(["start": "2026-10-23"], "start") }
    #expect(try LocalPortalRules.date(["start": "2026-10-23T09:00:00+08:00"], "start").ISO8601Format() == "2026-10-23T01:00:00Z")
}
