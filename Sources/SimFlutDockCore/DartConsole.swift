import Foundation

/// A separate VM-service connection makes Dart stdout/stderr specific to one app,
/// even when simctl logs from several executables all named Runner.
@MainActor public final class DartConsole {
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var rpc: MachineClient!
    private var closed = false
    public var onOutput: ((Data, Bool) -> Void)?
    public var onDisconnect: ((Error) -> Void)?
    public init() {
        rpc = MachineClient(arrayWrapped: false) { [weak self] data in
            guard let self, let socket = self.socket, !self.closed else { throw SimFlutDockError.exited }
            Task { [weak self] in
                do { try await socket.send(.string(String(decoding: data, as: UTF8.self))) }
                catch { self?.failed(error) }
            }
        }
    }
    public func connectAndResume(_ url: URL) async throws {
        // VM-service URLs come from the owned flutter process. Only local transports are needed.
        guard ["ws", "wss"].contains(url.scheme ?? ""), ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "") else {
            throw SimFlutDockError.message(L10n.text("Flutter returned an unsupported Dart VM address."))
        }
        let socket = URLSession.shared.webSocketTask(with: url); self.socket = socket; socket.resume()
        receiver = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    let data: Data
                    switch message { case .data(let bytes): data = bytes; case .string(let string): data = Data(string.utf8); @unknown default: continue }
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    self?.receive(object)
                } catch { if !Task.isCancelled { self?.failed(error) }; return }
            }
        }
        _ = try await rpc.request("streamListen", params: ["streamId": "Stdout"], timeout: 20)
        _ = try await rpc.request("streamListen", params: ["streamId": "Stderr"], timeout: 20)
        try await resumePausedIsolates()
    }
    public func resumePausedIsolates() async throws {
        let vm = try await rpc.request("getVM", params: [:], timeout: 20)
        let result = vm["result"] as? [String: Any]
        guard let isolates = result?["isolates"] as? [[String: Any]], !isolates.isEmpty else {
            throw SimFlutDockError.message(L10n.text("Dart VM did not return the main isolate."))
        }
        for isolate in isolates {
            guard let id = isolate["id"] as? String, isolate["isSystemIsolate"] as? Bool != true else { continue }
            let detail = try await rpc.request("getIsolate", params: ["isolateId": id], timeout: 20)
            let state = (detail["result"] as? [String: Any])?["pauseEvent"] as? [String: Any]
            if state?["kind"] as? String == "PauseStart" {
                _ = try await rpc.request("resume", params: ["isolateId": id], timeout: 20)
            }
        }
    }
    /// Heap usage of the main Dart isolate; not the application's total RSS.
    public func mainIsolateHeapBytes() async throws -> Int64? {
        guard !closed, socket != nil else { return nil }
        try Task.checkCancellation()
        let vm = try await rpc.request("getVM", params: [:], timeout: 4)
        guard let isolates = (vm["result"] as? [String: Any])?["isolates"] as? [[String: Any]],
              let main = isolates.first(where: { $0["name"] as? String == "main" && $0["isSystemIsolate"] as? Bool != true }),
              let id = main["id"] as? String else { return nil }
        try Task.checkCancellation()
        let usage = try await rpc.request("getMemoryUsage", params: ["isolateId": id], timeout: 4)
        return Self.heapBytes(from: usage)
    }

    nonisolated static func heapBytes(from response: [String: Any]) -> Int64? {
        guard let result = response["result"] as? [String: Any],
              result["type"] as? String == "MemoryUsage",
              let bytes = result["heapUsage"] as? NSNumber,
              CFGetTypeID(bytes) != CFBooleanGetTypeID(),
              bytes.doubleValue >= 0, bytes.doubleValue < Double(Int64.max),
              bytes.doubleValue.rounded(.towardZero) == bytes.doubleValue else { return nil }
        return bytes.int64Value
    }
    public func receive(_ object: [String: Any]) {
        if rpc.receive(object) { return }
        guard object["method"] as? String == "streamNotify", let params = object["params"] as? [String: Any],
              let stream = params["streamId"] as? String, ["Stdout", "Stderr"].contains(stream),
              let event = params["event"] as? [String: Any], event["kind"] as? String == "WriteEvent",
              let bytes = event["bytes"] as? String, let data = Data(base64Encoded: bytes) else { return }
        onOutput?(data, stream == "Stderr")
    }
    private func failed(_ error: Error) {
        guard !closed else { return }
        rpc.close(error: error); onDisconnect?(error); close()
    }
    public func close() {
        closed = true; rpc.close(); receiver?.cancel(); receiver = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
    }
}
