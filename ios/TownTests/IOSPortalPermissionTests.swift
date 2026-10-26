import XCTest
import HealthKit
@testable import Town

@MainActor final class IOSPortalPermissionTests: XCTestCase {
    private var home: URL!
    private var portal: IOSPortalStore!
    private var access: FakePortalPermissions!
    private var health: FakePortalHealth!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        access = FakePortalPermissions(); health = FakePortalHealth()
        portal = IOSPortalStore(base: home, permissions: access, health: health)
        portal.bind(try Connection("https://example.invalid/alice?token=test"))
    }
    override func tearDownWithError() throws { portal.stop(); portal = nil; try? FileManager.default.removeItem(at: home) }
    func testDeniedPromptNeverEnablesAndCanBeRetriedAfterSettings() async {
        await portal.requestGrant("calendar.read")
        XCTAssertFalse(portal.effectiveGrant("calendar.read"))
        XCTAssertFalse(portal.options.grants.contains("calendar.read"))
        XCTAssertEqual(access.requests, 1)
        await portal.requestGrant("calendar.read")
        XCTAssertEqual(access.requests, 1, "Denied permissions must route to Settings instead of silently retrying")
        access.state = .allowed
        portal.refreshPermissions()
        XCTAssertFalse(portal.effectiveGrant("calendar.read"), "Returning from Settings does not itself grant a Being access")
        await portal.requestGrant("calendar.read")
        XCTAssertTrue(portal.effectiveGrant("calendar.read"))
        access.state = .denied
        portal.resume()
        XCTAssertFalse(portal.options.grants.contains("calendar.read"))
    }
    func testWaitsForSystemResultAndDoesNotCrossBeing() async throws {
        access.suspend = true
        let request = Task { await portal.requestGrant("location.read") }
        while access.reply == nil { await Task.yield() }
        XCTAssertFalse(portal.effectiveGrant("location.read"))
        XCTAssertEqual(portal.authorizing, "location")
        portal.bind(try Connection("https://example.invalid/bob?token=test"))
        access.complete(.allowed)
        await request.value
        XCTAssertFalse(portal.options.grants.contains("location.read"))
    }
    func testRevokingDuringRequestDoesNotReenable() async {
        access.suspend = true
        let request = Task { await portal.requestGrant("location.read") }
        while access.reply == nil { await Task.yield() }
        portal.setGrant("location.read", enabled: false)
        access.complete(.allowed)
        await request.value
        XCTAssertFalse(portal.options.grants.contains("location.read"))
    }
    func testExistingIncorrectGrantsAreReconciled() throws {
        portal.configure { $0.grants = ["contacts.read", "contacts.write"] }
        let restored = IOSPortalStore(base: home, permissions: access, health: health)
        restored.bind(portal.connection)
        XCTAssertTrue(restored.options.grants.isEmpty)
        XCTAssertThrowsError(try restored.check("portal_ios_contacts"))
    }
    func testHealthConnectionOpensSystemSheetAndDoesNotClaimReadAuthorization() async throws {
        health.suspendAuthorization = true
        let request = Task { await portal.connectHealth() }
        while health.authorizationReply == nil { await Task.yield() }
        XCTAssertTrue(portal.options.grants.isEmpty, "Wait for system processing before completing the switch")
        XCTAssertEqual(health.authorizations, [Set(IOSPortalHealth.categories.map(\.id))])
        health.authorizationReply?.resume(); health.authorizationReply = nil
        let completed = await request.value
        XCTAssertTrue(completed)
        XCTAssertTrue(portal.healthLinked)
        let capabilities = try await portal.call("portal_ios_capabilities", [:])
        XCTAssertEqual((capabilities["health"] as? [String: Any])?["read_authorization"] as? String, "not_disclosed")
        let tool = try XCTUnwrap(portal.tools.first { $0["name"] as? String == "portal_ios_health" })
        let props = (tool["inputSchema"] as? [String: Any])?["properties"] as? [String: [String: Any]]
        XCTAssertEqual(Set(props?["category"]?["enum"] as? [String] ?? []), Set(IOSPortalHealth.categories.map(\.id)))
        do { _ = try await portal.call("portal_ios_health", ["category": "clinical_records"]); XCTFail("Unsupported category leaked") } catch {}
        XCTAssertEqual(health.reads, 0)
        portal.revokeHealthGrants()
        XCTAssertFalse(portal.tools.contains { $0["name"] as? String == "portal_ios_health" })
    }
    func testHealthCancelledSheetAndBeingSwitchRemainOff() async throws {
        health.fail = true
        let cancelled = await portal.connectHealth()
        XCTAssertFalse(cancelled)
        XCTAssertNotNil(portal.notice)
        XCTAssertTrue(portal.options.grants.isEmpty)
        health.fail = false; health.suspendAuthorization = true
        let request = Task { await portal.connectHealth() }
        while health.authorizationReply == nil { await Task.yield() }
        portal.bind(try Connection("https://example.invalid/bob?token=test"))
        health.authorizationReply?.resume(); health.authorizationReply = nil
        let stale = await request.value
        XCTAssertFalse(stale)
        XCTAssertTrue(portal.options.grants.isEmpty)
    }
    func testHealthImmediateCompletionAndFailedRetryAreDistinguished() async {
        let first = await portal.connectHealth()
        XCTAssertTrue(first)
        let repeated = await portal.connectHealth()
        XCTAssertTrue(repeated)
        health.fail = true
        let failed = await portal.connectHealth()
        XCTAssertFalse(failed, "An existing link must not hide a failed new request")
        XCTAssertTrue(portal.healthLinked)
        XCTAssertNotNil(portal.notice)
        XCTAssertFalse(portal.healthRequesting)
        health.fail = false
        let retried = await portal.connectHealth()
        XCTAssertTrue(retried)
        XCTAssertNil(portal.notice)
    }
    func testHealthSaveFailureDoesNotReportCompletion() async throws {
        try FileManager.default.removeItem(at: home)
        let completed = await portal.connectHealth()
        XCTAssertFalse(completed)
        XCTAssertFalse(portal.healthLinked)
        XCTAssertNotNil(portal.notice)
    }
    func testHealthRevocationDiscardsInFlightData() async throws {
        await portal.connectHealth()
        health.suspendRead = true
        let request = Task { try await portal.call("portal_ios_health", ["category": "steps"]) }
        while health.readReply == nil { await Task.yield() }
        portal.revokeHealthGrants()
        health.readReply?.resume(returning: ["records": [["value": 123]]]); health.readReply = nil
        do { _ = try await request.value; XCTFail("Revoked health data escaped") } catch {}
        XCTAssertTrue(portal.activity.isEmpty)
    }
    func testHealthContractReportsExactFieldsAndSupportsSevenDayDefault() async throws {
        await portal.connectHealth()
        let response = await portal.dispatch(["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "portal_ios_health", "arguments": ["metric": "sleep"]]])
        let result = response?["result"] as? [String: Any]
        let message = (result?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        XCTAssertEqual(result?["isError"] as? Bool, true)
        XCTAssertTrue(message.contains("缺少必填字段：category"))
        XCTAssertTrue(message.contains("不支持的字段：metric"))
        XCTAssertTrue(message.contains("{\"category\":\"sleep\"}"))
        let valid = await portal.dispatch(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "portal_ios_health", "arguments": ["category": "sleep"]]])
        XCTAssertEqual((valid?["result"] as? [String: Any])?["isError"] as? Bool, false)
        let now = Date(timeIntervalSince1970: 1800000000)
        let (start, end) = try IOSPortalHealth.range([:], now: now)
        XCTAssertEqual(end, now)
        XCTAssertEqual(end.timeIntervalSince(start), 7 * 86400)
        XCTAssertEqual(IOSPortalHealth.categories.count, 26)
        XCTAssertEqual(Set(IOSPortalHealth.categories.map(\.id)).count, 26)
        let oxygen = try XCTUnwrap(IOSPortalHealth.categories.first { $0.id == "oxygen_saturation" })
        let sample = HKQuantitySample(type: HKQuantityType(.oxygenSaturation), quantity: HKQuantity(unit: .percent(), doubleValue: 0.98), start: now, end: now)
        XCTAssertEqual(IOSPortalHealth.encode(sample, category: oxygen)["value"] as? Double, 98)
    }
    func testHealthRangeAndUnits() throws {
        XCTAssertThrowsError(try IOSPortalHealth.range(["start": "2026-01-01T00:00:00Z", "end": "2026-03-01T00:00:00Z"]))
        XCTAssertThrowsError(try IOSPortalHealth.range(["start": "2026-01-01T00:00:00Z", "end": "2025-01-01T00:00:00Z"]))
        let type = try XCTUnwrap(IOSPortalHealth.categories.first { $0.id == "body_mass" })
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gram(), doubleValue: 72000), start: Date(), end: Date())
        let row = IOSPortalHealth.encode(sample, category: type)
        XCTAssertEqual(row["value"] as? Double, 72)
        XCTAssertEqual(row["unit"] as? String, "kg")
        XCTAssertTrue(IOSPortalHealth.disclosure.contains("Empty results"))
    }
}

@MainActor private final class FakePortalPermissions: IOSPortalPermissions {
    var state = IOSPortalPermissionState.notDetermined
    var requests = 0
    var suspend = false
    var reply: CheckedContinuation<Void, Never>?
    func permission(_ capability: String) -> IOSPortalPermissionState { state }
    func authorize(_ capability: String) async throws {
        requests += 1
        if suspend { await withCheckedContinuation { reply = $0 } }
        else { state = .denied }
    }
    func complete(_ value: IOSPortalPermissionState) { state = value; reply?.resume(); reply = nil }
}
@MainActor private final class FakePortalHealth: IOSPortalHealthAccess {
    var available = true
    var fail = false
    var reads = 0
    var authorizations: [Set<String>] = []
    var suspendAuthorization = false
    var authorizationReply: CheckedContinuation<Void, Never>?
    var suspendRead = false
    var readReply: CheckedContinuation<[String: Any], Never>?
    func authorize(_ categories: Set<String>) async throws { authorizations.append(categories); if fail { throw CancellationError() }; if suspendAuthorization { await withCheckedContinuation { authorizationReply = $0 } } }
    func read(_ args: [String: Any]) async throws -> [String: Any] { reads += 1; if suspendRead { return await withCheckedContinuation { readReply = $0 } }; return ["records": [], "read_authorization": "not_disclosed"] }
}
