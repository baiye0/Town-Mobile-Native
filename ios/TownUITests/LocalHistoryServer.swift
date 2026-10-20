import Foundation
import Network
import XCTest

// Loopback-only fixture: exercises the real connection/history UI without an account.
final class LocalHistoryServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "town.compatibility.http")
    private let lock = NSLock()
    private var count = 60
    private var historyReceived: XCTestExpectation?
    var endpoint: String { "http://127.0.0.1:\(listener.port!.rawValue)/compat" }

    init(ready: XCTestExpectation) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    func appendMessage(received: XCTestExpectation) {
        lock.lock(); defer { lock.unlock() }
        count = 61
        historyReceived = received
    }

    func stop() { listener.cancel() }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            let buffer = buffer + (data ?? Data())
            guard let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete || error != nil || buffer.count > 65_536 { connection.cancel() }
                else { self.receive(connection, buffer: buffer) }
                return
            }
            let body = self.response(for: request)
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func response(for request: String) -> Data {
        var payload: [String: Any] = [:]
        if request.contains("/api/history") {
            lock.lock()
            let count = count
            let received = historyReceived
            historyReceived = nil
            lock.unlock()
            payload["messages"] = (1...count).map { index in
                ["seq": index, "role": "assistant", "scene_id": "fixture",
                 "content": String(format: "Compatibility message %03d", index)] as [String: Any]
            }
            received?.fulfill()
        } else if request.contains("/api/llm/config") {
            payload = ["sbs_enabled": false, "model": "fixture", "provider": "local"]
        }
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}
