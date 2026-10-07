import Foundation

public enum MachineOutput {
    case message([String: Any])
    case text(String)
}

public struct MachineParser {
    private var buffer = Data()
    private let parseMessages: Bool
    public init(parseMessages: Bool = true) { self.parseMessages = parseMessages }
    public mutating func feed(_ data: Data) -> [MachineOutput] {
        buffer.append(data)
        var output: [MachineOutput] = []
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            output += parse(line)
        }
        // Protect against a tool writing unlimited output without a newline.
        if buffer.count > 1_048_576 {
            output.append(.text(String(decoding: buffer, as: UTF8.self))); buffer.removeAll()
        }
        return output
    }
    public mutating func finish() -> [MachineOutput] {
        defer { buffer.removeAll() }
        return buffer.isEmpty ? [] : parse(buffer)
    }
    private func parse(_ data: Data) -> [MachineOutput] {
        if parseMessages, let messages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           !messages.isEmpty, messages.allSatisfy({ $0["event"] != nil || $0["id"] != nil }) {
            return messages.map { .message($0) }
        }
        return [.text(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines))]
    }
}

/// Owns one request table per process, including timeout and termination cleanup.
@MainActor public final class MachineClient {
    private struct Pending {
        let continuation: CheckedContinuation<[String: Any], Error>
        let timer: Task<Void, Never>
    }
    private var nextID = 0
    private var pending: [Int: Pending] = [:]
    private let arrayWrapped: Bool
    private let write: (Data) throws -> Void
    public var pendingCount: Int { pending.count }
    public init(arrayWrapped: Bool = true, write: @escaping (Data) throws -> Void) { self.arrayWrapped = arrayWrapped; self.write = write }
    public func request(_ method: String, params: [String: Any], timeout: TimeInterval = 30) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        let object: [String: Any] = ["id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: arrayWrapped ? [object] as Any : object as Any) + Data([10])
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }
                    catch { return }
                    self?.fail(id, error: SimFlutDockError.timeout(method))
                }
                pending[id] = Pending(continuation: continuation, timer: timer)
                do { try write(data) } catch { fail(id, error: error) }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.fail(id, error: CancellationError()) } })
    }
    @discardableResult public func receive(_ message: [String: Any]) -> Bool {
        guard let id = message["id"] as? Int, let item = pending.removeValue(forKey: id) else { return false }
        item.timer.cancel()
        if let error = message["error"] {
            item.continuation.resume(throwing: SimFlutDockError.message("Flutter: \(error)"))
        } else {
            item.continuation.resume(returning: message)
        }
        return true
    }
    public func close(error: Error = SimFlutDockError.exited) {
        for id in Array(pending.keys) { fail(id, error: error) }
    }
    private func fail(_ id: Int, error: Error) {
        guard let item = pending.removeValue(forKey: id) else { return }
        item.timer.cancel(); item.continuation.resume(throwing: error)
    }
}
