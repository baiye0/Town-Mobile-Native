import Foundation

extension IOSPortalStore {
    func launch() {
        cancelSession()
        guard wanted, let connection else { return }
        let epoch = generation
        setPhase("connecting")
        runner = Task { [weak self] in
            guard let self else { return }
            var delay = 2.0
            while !Task.isCancelled, self.wanted, self.generation == epoch {
                let began = Date()
                do {
                    self.setPhase("connecting")
                    let config = URLSessionConfiguration.ephemeral
                    config.timeoutIntervalForRequest = 20
                    config.httpShouldSetCookies = false; config.urlCache = nil
                    let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
                    self.session = session
                    let socket = session.webSocketTask(with: try LocalPortalRules.relayURL(connection))
                    socket.maximumMessageSize = 1024 * 1024
                    self.socket = socket; socket.resume()
                    let deadline = Task {
                        do { try await Task.sleep(for: .seconds(20)) } catch { return }
                        socket.cancel(with: .goingAway, reason: nil)
                    }
                    let hello: [String: Any]
                    do {
                        try await Self.send(["being_id": connection.being, "loom_token": connection.token, "portal_name": self.options.name], to: socket)
                        hello = try await Self.receive(socket)
                        deadline.cancel()
                    } catch { deadline.cancel(); throw error }
                    guard self.generation == epoch, !Task.isCancelled else { break }
                    guard hello["ok"] as? Bool == true else {
                        self.wanted = false; self.setPhase("invalid")
                        socket.cancel(with: .policyViolation, reason: nil); session.invalidateAndCancel(); break
                    }
                    self.lastSeen = Date(); self.setPhase("connected")
                    let textKeepalive = hello["relay_keepalive"] as? String == "text-v1"
                    let heartbeat = Task { [weak self] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .seconds(15)) } catch { return }
                            guard let self, self.generation == epoch else { return }
                            guard Date().timeIntervalSince(self.lastSeen) < 90 else { socket.cancel(with: .goingAway, reason: nil); return }
                            // A separate timeout also bounds a stalled send or ping callback.
                            let timeout = Task {
                                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                                socket.cancel(with: .goingAway, reason: nil)
                            }
                            do {
                                if textKeepalive { try await Self.send(["type": "keepalive"], to: socket) }
                                else {
                                    try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
                                        socket.sendPing { error in if let error { reply.resume(throwing: error) } else { reply.resume() } }
                                    }
                                    self.lastSeen = Date()
                                }
                                timeout.cancel()
                            } catch { timeout.cancel(); socket.cancel(with: .goingAway, reason: nil); return }
                        }
                    }
                    do {
                        while !Task.isCancelled, self.generation == epoch {
                            let request = try await Self.receive(socket)
                            self.lastSeen = Date()
                            if request["type"] as? String == "keepalive_ack" { continue }
                            guard self.generation == epoch, !Task.isCancelled else { break }
                            if self.calls.count >= 4 {
                                if let id = request["id"] { try await Self.send(["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": "Portal busy; retry later"]], to: socket) }
                                continue
                            }
                            let callID = UUID()
                            self.calls[callID] = Task { [weak self] in
                                guard let self else { return }
                                defer { self.calls.removeValue(forKey: callID) }
                                if let response = await self.dispatch(request), self.generation == epoch, !Task.isCancelled {
                                    do { try await Self.send(response, to: socket) }
                                    catch { socket.cancel(with: .goingAway, reason: nil) }
                                }
                            }
                        }
                        heartbeat.cancel()
                    } catch { heartbeat.cancel(); throw error }
                } catch {
                    // Never expose server errors, URLs or handshake contents (which may echo a token).
                }
                guard self.generation == epoch else { break }
                self.calls.values.forEach { $0.cancel() }; self.calls.removeAll()
                self.interruptActivities()
                self.socket?.cancel(with: .goingAway, reason: nil)
                self.session?.invalidateAndCancel()
                guard self.generation == epoch, self.wanted, !Task.isCancelled else { break }
                self.native.cancelLocation()
                if Date().timeIntervalSince(began) > 60 { delay = 2 }
                self.setPhase("retrying")
                do { try await Task.sleep(for: .seconds(delay * Double.random(in: 0.7...1.3))) } catch { break }
                delay = min(30, delay * 2)
            }
        }
    }
    nonisolated static func send(_ value: [String: Any], to socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= 1024 * 1024, let string = String(data: data, encoding: .utf8) else { throw PortalError.invalidResponse }
        try await socket.send(.string(string))
    }
    nonisolated static func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let message = try await socket.receive()
        let data: Data
        switch message { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: throw PortalError.invalidResponse }
        guard data.count <= 1024 * 1024, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PortalError.invalidResponse }
        return value
    }
}
