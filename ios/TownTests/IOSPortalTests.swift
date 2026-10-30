import XCTest
import Network
import EventKit
import Contacts
import HealthKit
@testable import Town

@MainActor final class IOSPortalTests: XCTestCase {
    private var home: URL!
    private var portal: IOSPortalStore!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("portal-tests-" + UUID().uuidString)
        portal = IOSPortalStore(base: home)
        portal.bind(try Connection("https://example.invalid/alice?token=synthetic"))
    }
    override func tearDownWithError() throws { portal.stop(); portal = nil; try? FileManager.default.removeItem(at: home) }
    private func requireNativeSimulator() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Native Portal QA must run on an isolated simulator")
        #endif
    }
    private func rpc(_ name: String, _ args: [String: Any] = [:]) async -> [String: Any] {
        let response = await portal.dispatch(["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": args]])
        return response ?? [:]
    }
    private func result(_ response: [String: Any]) throws -> [String: Any] {
        let content = (response["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let text = try XCTUnwrap(content?.first?["text"] as? String)
        return try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] ?? [:]
    }
    func testHealthKitQueriesAllSupportedTypesOnIsolatedSimulator() async throws {
        try requireNativeSimulator()
        guard portal.health.available else { throw XCTSkip("HealthKit unavailable") }
        let types = Set(IOSPortalHealth.categories.filter { !$0.id.hasPrefix("blood_pressure_") }.map { $0.type as HKObjectType })
        guard try await HKHealthStore().statusForAuthorizationRequest(toShare: [], read: types) == .unnecessary else {
            throw XCTSkip("Run testPortalHealthSuccessfulConnection first on this isolated simulator")
        }
        // Run after the UI HealthKit sheet fixture on this isolated simulator.
        // No personal records are seeded, requested, or written by this test.
        var completed = 0
        for category in IOSPortalHealth.categories {
            do {
                let result = try await portal.health.read(["category": category.id])
                XCTAssertEqual(result["category"] as? String, category.id)
                XCTAssertEqual(result["read_authorization"] as? String, "not_disclosed")
                XCTAssertNotNil(result["records"] as? [[String: Any]])
                XCTAssertEqual(result["truncated"] as? Bool, false)
                completed += 1
            } catch {
                // This simulator runtime omits blood pressure from its system
                // sharing sheet. Preserve the explicit error; never invent data.
                guard category.id.hasPrefix("blood_pressure_"), error.localizedDescription.contains("HealthKit 错误 5") else { throw error }
            }
        }
        XCTAssertGreaterThanOrEqual(completed, 24)
    }

    func testMCPFileLifecycleAndRevocation() async throws {
        let hello = await portal.dispatch(["jsonrpc": "2.0", "id": "init", "method": "initialize"])
        XCTAssertEqual(hello?["id"] as? String, "init")
        XCTAssertEqual((hello?["result"] as? [String: Any])?["protocolVersion"] as? String, "2024-11-05")
        let written = await rpc("portal_file_write", ["path": "notes/hello.txt", "content": "first\n世界"])
        XCTAssertEqual(try result(written)["written"] as? Int, 12)
        let read = await rpc("portal_file_read", ["path": "notes/hello.txt", "offset": 1, "limit": 1])
        XCTAssertEqual(try result(read)["text"] as? String, "世界")
        let edited = await rpc("portal_file_edit", ["path": "notes/hello.txt", "old_text": "first", "new_text": "next"])
        XCTAssertEqual(try result(edited)["replacements"] as? Int, 1)
        let traversal = await rpc("portal_file_write", ["path": "../options.json", "content": "bad"])
        XCTAssertEqual((traversal["result"] as? [String: Any])?["isError"] as? Bool, true)
        let unsupported = await rpc("portal_file_write", ["path": "notes/hello.txt", "content": "bad", "unescape": true])
        XCTAssertEqual((unsupported["result"] as? [String: Any])?["isError"] as? Bool, true)
        let notification = await portal.dispatch(["jsonrpc": "2.0", "method": "tools/call", "params": ["name": "portal_file_write", "arguments": ["path": "unexpected", "content": "bad"]]])
        XCTAssertNil(notification)
        XCTAssertThrowsError(try portal.workspace?.read("unexpected"))
        portal.configure { $0.files = false }
        let disabled = await rpc("portal_file_read", ["path": "notes/hello.txt"])
        XCTAssertNotNil(disabled["error"])
        XCTAssertFalse(portal.tools.contains { ($0["name"] as? String)?.hasPrefix("portal_file") == true })
    }
    func testOwnershipAndCorruptPolicyFailClosed() throws {
        try portal.workspace?.write("private.txt", data: Data("alice".utf8))
        // Ownership persistence is independent of simulator system grants.
        portal.configure { $0.grants.insert("health.steps.read") }
        portal.bind(try Connection("https://example.invalid/bob?token=synthetic"))
        XCTAssertTrue(portal.options.grants.isEmpty)
        XCTAssertThrowsError(try portal.workspace?.read("private.txt"))
        portal.bind(try Connection("https://example.invalid/alice?token=rotated"))
        XCTAssertEqual(try portal.workspace?.read("private.txt"), Data("alice".utf8))
        XCTAssertTrue(portal.options.grants.contains("health.steps.read"))
        let owner = LocalPortalRules.owner(try XCTUnwrap(portal.connection))
        try Data("corrupt".utf8).write(to: home.appendingPathComponent(owner).appendingPathComponent("options.json"))
        let restored = IOSPortalStore(base: home); restored.bind(portal.connection)
        restored.start()
        XCTAssertFalse(restored.running)
        XCTAssertNil(restored.workspace)
        XCTAssertNotNil(restored.notice)
    }
    func testActivityTracksReadsFailuresWithoutPollingNoiseAndIsBounded() async throws {
        _ = await rpc("portal_file_read", ["path": "missing.txt"])
        XCTAssertEqual(portal.activity.first?.status, "失败")
        _ = await rpc("portal_ios_activity")
        _ = await rpc("portal_status")
        XCTAssertEqual(portal.activity.count, 1)
        for _ in 0..<105 { portal.record("portal_file_read", "已完成") }
        XCTAssertEqual(portal.activity.count, 100)
        await portal.flushActivity()
        let owner = LocalPortalRules.owner(try XCTUnwrap(portal.connection))
        let data = try Data(contentsOf: home.appendingPathComponent(owner).appendingPathComponent("activity.json"))
        let records = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        XCTAssertEqual(records.count, 100)
        XCTAssertEqual(Set(records[0].keys), ["id", "time", "tool", "status"])
    }
    func testImmediateOwnerSwitchRetainsActivityBeforeDiskFlush() throws {
        let alice = try XCTUnwrap(portal.connection)
        portal.record("portal_file_read", "已完成")
        let id = portal.activity.first?.id
        portal.bind(try Connection("https://example.invalid/bob?token=synthetic"))
        XCTAssertTrue(portal.activity.isEmpty)
        portal.bind(alice)
        XCTAssertEqual(portal.activity.first?.id, id)
    }
    func testResumeRepairsStaleAndRetryingSessionsWithoutRestartingManualStop() {
        portal.start()
        portal.setPhase("retrying")
        var epoch = portal.generation
        portal.resume()
        XCTAssertNotEqual(portal.generation, epoch)
        XCTAssertEqual(portal.phase, "connecting")
        portal.setPhase("connected")
        portal.lastSeen = Date().addingTimeInterval(-100)
        epoch = portal.generation
        portal.resume()
        XCTAssertNotEqual(portal.generation, epoch)
        portal.suspend()
        XCTAssertTrue(portal.running)
        portal.resume()
        XCTAssertEqual(portal.phase, "connecting")
        portal.stop()
        epoch = portal.generation
        portal.resume()
        XCTAssertEqual(portal.generation, epoch)
        XCTAssertFalse(portal.running)
        XCTAssertEqual(portal.phase, "stopped")
    }
    func testPermissionPersistenceFailureStopsAccess() async throws {
        portal.configure { $0.grants.insert("calendar.read") }
        let owner = LocalPortalRules.owner(try XCTUnwrap(portal.connection))
        let journal = home.appendingPathComponent(owner).appendingPathComponent("actions.json")
        try FileManager.default.removeItem(at: journal)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: false)
        try Data().write(to: journal.appendingPathComponent("block-write"))
        portal.configure { $0.grants.remove("calendar.read") }
        XCTAssertFalse(portal.running)
        XCTAssertNil(portal.workspace)
        XCTAssertThrowsError(try portal.check("portal_ios_calendar"))
        let response = await rpc("portal_file_write", ["path": "must-not-write", "content": "data"])
        XCTAssertEqual((response["result"] as? [String: Any])?["isError"] as? Bool, true)
    }
    func testNativeDeniedUntilBeingAndSystemPermissionsBothExist() async throws {
        XCTAssertThrowsError(try portal.check("portal_ios_calendar"))
        XCTAssertThrowsError(try portal.enqueue("portal_ios_calendar", args: ["action": "delete", "id": "fake", "request_id": "a"]))
        XCTAssertTrue(portal.actions.isEmpty)
        portal.configure { $0.grants.insert("calendar.read") }
        let tool = try XCTUnwrap(portal.tools.first { $0["name"] as? String == "portal_ios_calendar" })
        let schema = tool["inputSchema"] as? [String: Any]
        let props = schema?["properties"] as? [String: [String: Any]]
        XCTAssertEqual(props?["action"]?["enum"] as? [String], ["list", "get", "calendars"])
        let deniedWrite = await rpc("portal_ios_calendar", ["action": "delete", "id": "fake"])
        XCTAssertEqual((deniedWrite["result"] as? [String: Any])?["isError"] as? Bool, true)
        if !portal.native.available("calendar") { XCTAssertThrowsError(try portal.check("portal_ios_calendar")) }
    }
    func testInterruptedWriteRestoresAsUnknown() throws {
        let args: [String: Any] = ["request_id": "one", "action": "create", "title": "Synthetic reminder"]
        var action = IOSPortalAction(id: "one", tool: "portal_ios_reminders", arguments: try JSONSerialization.data(withJSONObject: args), fingerprint: try LocalPortalRules.fingerprint(tool: "portal_ios_reminders", arguments: args))
        action.state = "executing"
        let owner = LocalPortalRules.owner(try XCTUnwrap(portal.connection))
        try JSONEncoder().encode([action]).write(to: home.appendingPathComponent(owner).appendingPathComponent("actions.json"))
        let restored = IOSPortalStore(base: home); restored.bind(portal.connection)
        XCTAssertEqual(restored.actions.first?.state, "unknown")
        XCTAssertEqual(restored.actions.first?.state, "unknown")
    }
    func testNativeCalendarImmediateDedupAndDeletion() async throws {
        try requireNativeSimulator()
        guard portal.native.available("calendar") else { throw XCTSkip("Requires calendar grant on an isolated simulator") }
        portal.configure { $0.grants.formUnion(["calendar.read", "calendar.write"]) }
        let title = "Portal synthetic " + UUID().uuidString
        let start = Date().addingTimeInterval(3600), end = start.addingTimeInterval(1800)
        let args: [String: Any] = ["action": "create", "request_id": "calendar-create", "title": title, "start": start.ISO8601Format(), "end": end.ISO8601Format()]
        let created = try portal.enqueue("portal_ios_calendar", args: args)
        XCTAssertEqual(created["status"] as? String, "completed")
        XCTAssertEqual(portal.actions.first?.state, "completed", portal.notice ?? "")
        let resultData = try XCTUnwrap(portal.actions.first?.result)
        let record = try JSONSerialization.jsonObject(with: resultData) as! [String: Any]
        let id = try XCTUnwrap(record["id"] as? String)
        defer { if let event = portal.native.events.event(withIdentifier: id) { try? portal.native.events.remove(event, span: .thisEvent, commit: true) } }
        XCTAssertEqual(try portal.enqueue("portal_ios_calendar", args: args)["status"] as? String, "completed")
        XCTAssertEqual(portal.actions.count, 1)
        var conflict = args; conflict["title"] = "different"
        XCTAssertThrowsError(try portal.enqueue("portal_ios_calendar", args: conflict))
        let updated = try portal.enqueue("portal_ios_calendar", args: ["action": "update", "id": id, "request_id": "calendar-update", "title": "Updated request", "start": start.ISO8601Format(), "end": end.ISO8601Format()])
        XCTAssertEqual(updated["status"] as? String, "completed")
        XCTAssertEqual(portal.native.events.event(withIdentifier: id)?.title, "Updated request")
        let delete: [String: Any] = ["action": "delete", "id": id, "request_id": "calendar-delete"]
        let deleted = try portal.enqueue("portal_ios_calendar", args: delete)
        XCTAssertEqual(deleted["status"] as? String, "completed")
        XCTAssertNil(portal.native.events.event(withIdentifier: id))
        XCTAssertEqual(portal.actions.last?.state, "completed")
    }
    func testNativeContactsImmediateAndRevocation() throws {
        try requireNativeSimulator()
        guard portal.native.available("contacts") else { throw XCTSkip("Requires contacts grant on an isolated simulator") }
        portal.configure { $0.grants.formUnion(["contacts.read", "contacts.write"]) }
        let name = "Portal synthetic " + UUID().uuidString
        let args: [String: Any] = ["action": "create", "request_id": "contact-create", "given_name": name, "phones": ["5550100"]]
        let created = try portal.enqueue("portal_ios_contacts", args: args)
        XCTAssertEqual(created["status"] as? String, "completed")
        XCTAssertEqual(portal.actions.first?.state, "completed", portal.notice ?? "")
        let record = try JSONSerialization.jsonObject(with: XCTUnwrap(portal.actions.first?.result)) as! [String: Any]
        let id = try XCTUnwrap(record["id"] as? String)
        defer { _ = try? portal.native.write("contacts", ["action": "delete", "id": id]) }
        let updated = try portal.enqueue("portal_ios_contacts", args: ["action": "update", "id": id, "request_id": "contact-update", "given_name": "Updated synthetic", "phones": ["5550101"]])
        XCTAssertEqual(updated["status"] as? String, "completed")
        portal.configure { $0.grants.remove("contacts.write") }
        XCTAssertThrowsError(try portal.enqueue("portal_ios_contacts", args: ["action": "update", "id": id, "request_id": "contact-revoked", "given_name": "Should not apply"]))
        let contact = try portal.native.contacts.unifiedContact(withIdentifier: id, keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor])
        XCTAssertEqual(contact.givenName, "Updated synthetic")
    }
    func testLocationReturnsFreshCoordinatesAndAccuracy() async throws {
        try requireNativeSimulator()
        guard portal.native.available("location") else { throw XCTSkip("Requires simulated location grant") }
        portal.configure { $0.grants.insert("location.read") }
        let value = try await portal.call("portal_ios_location", ["action": "get"])
        XCTAssertEqual(try XCTUnwrap(value["latitude"] as? Double), 31.2304, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(value["longitude"] as? Double), 121.4737, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(value["accuracy_m"] as? Double), 0)
        XCTAssertNotNil(value["timestamp"])
    }
    func testNativeReminderImmediateAndCompletion() throws {
        try requireNativeSimulator()
        guard portal.native.available("reminders") else { throw XCTSkip("Requires reminders grant on an isolated simulator") }
        portal.configure { $0.grants.formUnion(["reminders.read", "reminders.write"]) }
        let created = try portal.enqueue("portal_ios_reminders", args: ["action": "create", "request_id": "reminder-create", "title": "Portal synthetic " + UUID().uuidString, "due": Date().addingTimeInterval(86400).ISO8601Format()])
        XCTAssertEqual(created["status"] as? String, "completed")
        XCTAssertEqual(portal.actions.first?.state, "completed", portal.notice ?? "")
        let record = try JSONSerialization.jsonObject(with: XCTUnwrap(portal.actions.first?.result)) as! [String: Any]
        let id = try XCTUnwrap(record["id"] as? String)
        defer { if let reminder = portal.native.events.calendarItem(withIdentifier: id) as? EKReminder { try? portal.native.events.remove(reminder, commit: true) } }
        let completed = try portal.enqueue("portal_ios_reminders", args: ["action": "update", "id": id, "request_id": "reminder-complete", "completed": true])
        XCTAssertEqual(completed["status"] as? String, "completed")
        XCTAssertEqual((portal.native.events.calendarItem(withIdentifier: id) as? EKReminder)?.isCompleted, true)
        let deleted = try portal.enqueue("portal_ios_reminders", args: ["action": "delete", "id": id, "request_id": "reminder-delete"])
        XCTAssertEqual(deleted["status"] as? String, "completed")
        XCTAssertNil(portal.native.events.calendarItem(withIdentifier: id))
    }
    func testRealWebSocketHandshakeMCPAndBackgroundResume() async throws {
        let ready = expectation(description: "listener")
        let handshake = expectation(description: "handshake")
        let fileRead = expectation(description: "file read over relay")
        let server = try PortalRelayFixture(ready: ready)
        defer { server.stop() }
        server.onMessage = { message, connection in
            if message["being_id"] != nil {
                XCTAssertEqual(message["being_id"] as? String, "fixture")
                XCTAssertEqual(message["loom_token"] as? String, "synthetic")
                XCTAssertTrue((message["portal_name"] as? String)?.hasPrefix("ios-") == true)
                server.send(["ok": true, "relay_keepalive": "text-v1"], on: connection)
                server.send(["jsonrpc": "2.0", "id": 11, "method": "initialize"], on: connection)
                handshake.fulfill()
            } else if message["id"] as? Int == 11 {
                XCTAssertEqual((message["result"] as? [String: Any])?["protocolVersion"] as? String, "2024-11-05")
                server.send(["jsonrpc": "2.0", "id": 12, "method": "tools/call", "params": ["name": "portal_file_write", "arguments": ["path": "relay.txt", "content": "relay works"]]], on: connection)
            } else if message["id"] as? Int == 12 {
                server.send(["jsonrpc": "2.0", "id": 13, "method": "tools/call", "params": ["name": "portal_file_read", "arguments": ["path": "relay.txt"]]], on: connection)
            } else if message["id"] as? Int == 13 {
                let content = (message["result"] as? [String: Any])?["content"] as? [[String: Any]]
                XCTAssertTrue((content?.first?["text"] as? String)?.contains("relay works") == true)
                fileRead.fulfill()
            }
        }
        await fulfillment(of: [ready], timeout: 5)
        portal.bind(try Connection("http://127.0.0.1:\(server.port)/fixture?token=synthetic"))
        portal.start()
        await fulfillment(of: [handshake, fileRead], timeout: 10)
        XCTAssertEqual(portal.phase, "connected")
        portal.suspend(); XCTAssertEqual(portal.phase, "paused"); XCTAssertTrue(portal.running)
        let resumed = expectation(description: "resumed")
        server.onMessage = { message, connection in
            if message["being_id"] != nil { server.send(["ok": true], on: connection); resumed.fulfill() }
        }
        portal.resume()
        await fulfillment(of: [resumed], timeout: 10)
        portal.bind(try Connection("https://example.invalid/other?token=synthetic"))
        XCTAssertFalse(portal.running)
        XCTAssertEqual(portal.phase, "stopped")
        XCTAssertNil(portal.socket)
    }
    func testRejectedRelayHandshakeStopsWithoutEchoingSecrets() async throws {
        let ready = expectation(description: "listener")
        let server = try PortalRelayFixture(ready: ready)
        defer { server.stop() }
        server.onMessage = { _, connection in server.send(["ok": false, "error": "synthetic-private-token"], on: connection) }
        await fulfillment(of: [ready], timeout: 5)
        portal.bind(try Connection("http://127.0.0.1:\(server.port)/fixture?token=synthetic")); portal.start()
        for _ in 0..<100 { if portal.phase == "invalid" { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(portal.phase, "invalid"); XCTAssertFalse(portal.running)
        XCTAssertFalse((portal.notice ?? "").contains("synthetic-private-token"))
    }
}

private final class PortalRelayFixture: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "town.portal.test.relay")
    private let lock = NSLock()
    private var handler: (([String: Any], NWConnection) -> Void)?
    private var connections: [NWConnection] = []
    var port: UInt16 { listener.port!.rawValue }
    var onMessage: (([String: Any], NWConnection) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return handler }
        set { lock.lock(); defer { lock.unlock() }; handler = newValue }
    }
    init(ready: XCTestExpectation) throws {
        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options(); websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection); connection.start(queue: self.queue); self.receive(connection)
        }
        listener.start(queue: queue)
    }
    func send(_ object: [String: Any], on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: UUID().uuidString, metadata: [metadata])
        connection.send(content: try! JSONSerialization.data(withJSONObject: object), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil else { return }
            if let data, let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.onMessage?(message, connection) }
            self.receive(connection)
        }
    }
    func stop() { listener.cancel(); queue.async { self.connections.forEach { $0.cancel() }; self.connections.removeAll(); self.onMessage = nil } }
}
