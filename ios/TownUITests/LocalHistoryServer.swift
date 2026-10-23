import Foundation
import Network
import XCTest
import UIKit

// Loopback-only fixture: exercises the real connection/history UI without an account.
final class LocalHistoryServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "town.compatibility.http")
    private let lock = NSLock()
    private var count = 60
    private var stream: NWConnection?
    private var chatRows: [[String: Any]] = []
    private var chatScene = ""
    private var chatEnabled = false
    private var stagedChat = false
    private var replyText = ""
    private var streamID = ""
    private var sent: [String] = []
    private var imageRequests: [String] = []
    var imageURL: String { endpoint + "/markdown-preview?token=signed%2Bvalue%2Fpart&expires=123" }
    var capturedImageRequests: [String] { lock.lock(); defer { lock.unlock() }; return imageRequests }
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

    var sentMessages: [String] { lock.lock(); defer { lock.unlock() }; return sent }
    func enableChat(staged: Bool = false) { lock.lock(); chatEnabled = true; stagedChat = staged; lock.unlock() }

    func emitProgress(_ type: String, _ fields: [String: Any]) {
        queue.async { self.emit(type, fields) }
    }

    func appendReply(_ text: String) {
        queue.async { self.replyText += text; self.emit("content_block_delta", ["delta": ["text": text]]) }
    }

    func nextReply() {
        queue.async {
            self.persistReply()
            self.emit("message_stop", [:])
            self.replyText = "Second streamed reply."
            self.emit("content_block_delta", ["delta": ["text": self.replyText]])
        }
    }

    func finishReply() {
        queue.async {
            guard self.stream != nil else { return }
            self.persistReply()
            self.emit("message_stop", [:])
            self.sendChunk("data: [DONE]\n\n")
            let stream = self.stream
            self.stream = nil
            stream?.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { _ in stream?.cancel() })
        }
    }

    func stop() { queue.async { self.stream?.cancel(); self.stream = nil }; listener.cancel() }

    private func persistReply() {
        guard !replyText.isEmpty else { return }
        lock.lock()
        let sequence = 61 + chatRows.count
        chatRows.append(["seq": sequence, "role": "assistant", "scene_id": chatScene, "content": replyText])
        lock.unlock()
        emit("meta", ["persisted": ["kind": "self", "from": "final", "seq": sequence, "stream_id": streamID]])
    }

    private func emit(_ type: String, _ fields: [String: Any]) {
        var fields = fields; fields["scene_id"] = chatScene
        let data = try! JSONSerialization.data(withJSONObject: fields)
        sendChunk("event: \(type)\ndata: \(String(decoding: data, as: UTF8.self))\n\n")
    }

    private func sendChunk(_ frame: String) {
        let data = Data(frame.utf8)
        stream?.send(content: Data("\(String(data.count, radix: 16))\r\n".utf8) + data + Data("\r\n".utf8), completion: .contentProcessed { _ in })
    }

    private func openStream(_ connection: NWConnection, request: String) {
        let body = request.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
        let payload = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        chatScene = payload["scene_id"] as? String ?? "fixture"
        let prompt = payload["message"] as? String ?? ""
        lock.lock()
        sent.append(prompt)
        chatRows.append(["seq": 61 + chatRows.count, "role": "user", "scene_id": chatScene, "content": prompt])
        lock.unlock()
        stream = connection
        streamID = UUID().uuidString
        connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in })
        emit("meta", ["stream_id": streamID])
        lock.lock(); let staged = stagedChat; lock.unlock()
        if staged {
            replyText = ""
            // These must not tear down the transport or force history recovery.
            sendChunk(": keepalive\n\nevent: ping\ndata: keepalive\n\n")
            emit("reasoning", ["delta": ["text": "正在检查上下文"]])
            return
        }
        replyText = "First streamed reply."
        emit("content_block_delta", ["delta": ["text": replyText]])
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            let buffer = buffer + (data ?? Data())
            guard let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete || error != nil || buffer.count > 65_536 { connection.cancel() }
                else { self.receive(connection, buffer: buffer) }
                return
            }
            let headers = request.components(separatedBy: "\r\n\r\n")[0]
            let length = headers.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            let headerBytes = headers.utf8.count + 4
            if buffer.count < headerBytes + length {
                self.receive(connection, buffer: buffer); return
            }
            if headers.contains("/markdown-preview?") {
                let location = self.endpoint + "/markdown-image?token=signed%2Bvalue%2Fpart&expires=123"
                let response = "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            if headers.contains("/markdown-image?") {
                self.lock.lock(); self.imageRequests.append(headers); let first = self.imageRequests.count == 1; self.lock.unlock()
                let data = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360)).pngData { context in
                    UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
                    ("Markdown image preview" as NSString).draw(at: CGPoint(x: 40, y: 150), withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.white])
                }
                let body = first ? Data() : data
                let header = "HTTP/1.1 \(first ? "503 Unavailable" : "200 OK")\r\nContent-Type: image/png\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            self.lock.lock(); let chat = self.chatEnabled; self.lock.unlock()
            if chat, headers.contains("/api/chat/stream") { self.openStream(connection, request: request); return }
            if chat, headers.contains("/api/stop") {
                self.persistReply()
                self.stream?.cancel(); self.stream = nil
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
            let rows = chatRows
            let received = historyReceived
            historyReceived = nil
            lock.unlock()
            payload["messages"] = (1...count).map { index in
                ["seq": index, "role": "assistant", "scene_id": "fixture",
                 "content": String(format: "Compatibility message %03d", index)] as [String: Any]
            }
            payload["messages"] = (payload["messages"] as! [[String: Any]]) + rows
            received?.fulfill()
        } else if request.contains("/api/llm/config") {
            payload = ["sbs_enabled": false, "model": "fixture", "provider": "local"]
        }
        return try! JSONSerialization.data(withJSONObject: payload)
    }
}
