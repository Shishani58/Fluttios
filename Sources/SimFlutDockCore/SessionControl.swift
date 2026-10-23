import CoreFoundation
import Foundation

/// The panel and MCP share the same session objects; this layer never launches a process.
@MainActor public final class SessionControl {
    private struct ControlError: Error {
        let code: String
        let message: String
    }
    private final class Command {
        let fingerprint: [String]
        var task: Task<[String: Any], Never>!
        var completed = false
        init(_ fingerprint: [String]) { self.fingerprint = fingerprint }
    }
    private let manager: SessionManager
    private var commands: [String: Command] = [:]
    private var commandOrder: [String] = []
    private var busySessions: Set<UUID> = []

    public init(manager: SessionManager) { self.manager = manager }

    public func handle(_ data: Data) async -> Data {
        let result: [String: Any]
        do {
            guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                Set(request.keys) == ["tool", "arguments"],
                let tool = request["tool"] as? String,
                let arguments = request["arguments"] as? [String: Any]
            else { throw invalidArguments() }
            result = try await call(tool, arguments)
        } catch let error as ControlError {
            result = failure(error.code, error.message)
        } catch {
            result = failure("INVALID_ARGUMENTS", "Expected a JSON object containing tool and arguments.")
        }
        // Every result is constructed from JSON primitives.
        return try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    private func call(_ tool: String, _ args: [String: Any]) async throws -> [String: Any] {
        switch tool {
        case "list_sessions":
            guard args.isEmpty else { throw invalidArguments() }
            let sessions = manager.sessions.values.filter { $0.launchProject != nil }
                .sorted { $0.id.uuidString < $1.id.uuidString }.map(snapshot)
            return success(["sessions": sessions])
        case "get_session", "read_logs":
            let allowed: Set<String> = tool == "read_logs" ? ["session_id", "cursor", "limit"] : ["session_id"]
            guard Set(args.keys).isSubset(of: allowed) else { throw invalidArguments() }
            let session = try findSession(args)
            if tool == "get_session" { return success(["session": snapshot(session)]) }
            return try readLogs(session, args)
        case "hot_reload", "hot_restart", "stop_session":
            guard Set(args.keys) == ["session_id", "launch_id", "request_id"],
                let sessionID = args["session_id"] as? String, let sessionUUID = UUID(uuidString: sessionID),
                let launchID = args["launch_id"] as? String, let launchUUID = UUID(uuidString: launchID),
                let requestID = args["request_id"] as? String,
                !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                requestID.utf8.count <= 128
            else { throw invalidArguments() }
            let fingerprint = [tool, sessionUUID.uuidString, launchUUID.uuidString]
            if let previous = commands[requestID] {
                guard previous.fingerprint == fingerprint else {
                    throw ControlError(
                        code: "REQUEST_ID_CONFLICT", message: "Use this request_id only for the original command.")
                }
                return await previous.task.value
            }
            let session = try findSession(args)
            guard session.launchID == launchUUID else {
                return failure("STALE_LAUNCH", "The session has a different launch. Read its current state.", session)
            }
            guard !manager.shuttingDown else {
                return failure("SHUTTING_DOWN", "Fluttios is shutting down.", session)
            }
            guard !busySessions.contains(session.id),
                !session.state.isBusy || (tool == "stop_session" && session.canStop)
            else {
                return failure("BUSY", "Another operation is in progress. Read the session state.", session)
            }
            guard tool == "stop_session" ? session.canStop : (session.canRestart && session.appID != nil) else {
                return failure(
                    "ACTION_UNAVAILABLE", "This action is unavailable in the current state or launch mode.", session)
            }
            // Bounded retry history. Never evict a request that is still executing.
            if commands.count >= 128 {
                guard let index = commandOrder.firstIndex(where: { commands[$0]?.completed == true }) else {
                    return failure("BUSY", "Too many commands are in progress.", session)
                }
                commands.removeValue(forKey: commandOrder.remove(at: index))
            }
            let command = Command(fingerprint)
            commands[requestID] = command
            commandOrder.append(requestID)
            busySessions.insert(session.id)
            // Start before yielding so a panel action cannot overtake acceptance.
            let operation: Task<Void, Never>?
            if tool == "stop_session" {
                session.stop()
                operation = nil
            } else {
                operation = session.restart(full: tool == "hot_restart")
            }
            command.task = Task { [self] in
                defer {
                    busySessions.remove(session.id)
                    command.completed = true
                }
                if let operation { await operation.value }
                if tool == "stop_session" {
                    let deadline = Date().addingTimeInterval(20)
                    while session.launchID == launchUUID && session.hasWork && Date() < deadline {
                        try? await Task.sleep(nanoseconds: 20_000_000)
                    }
                }
                busySessions.remove(session.id)
                guard session.launchID == launchUUID else {
                    return failure("STALE_LAUNCH", "The launch changed while the command was executing.", session)
                }
                if tool == "stop_session" {
                    guard !session.hasWork else {
                        return failure(
                            "COMMAND_TIMEOUT",
                            "Stop has not finished. Inspect the session before taking another action.", session)
                    }
                } else {
                    guard session.state == .running, session.error == nil else {
                        return failure(
                            "COMMAND_FAILED", session.error ?? "The app did not return to running state.", session)
                    }
                }
                return success(["status": "completed", "request_id": requestID, "session": snapshot(session)])
            }
            return await command.task.value
        default:
            throw ControlError(code: "UNKNOWN_TOOL", message: "Unknown session tool.")
        }
    }

    private func findSession(_ args: [String: Any]) throws -> FlutterSession {
        guard let text = args["session_id"] as? String, let id = UUID(uuidString: text) else {
            throw invalidArguments()
        }
        guard let session = manager.sessions.values.first(where: { $0.id == id && $0.launchProject != nil }) else {
            throw ControlError(code: "SESSION_NOT_FOUND", message: "Session not found. List sessions again.")
        }
        return session
    }

    private func readLogs(_ session: FlutterSession, _ args: [String: Any]) throws -> [String: Any] {
        var limit = 100
        if let value = args["limit"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                number.doubleValue == Double(number.intValue), (1...200).contains(number.intValue)
            else { throw invalidArguments() }
            limit = number.intValue
        }
        var start = 0
        var cursor: String?
        if let value = args["cursor"] {
            guard let text = value as? String, let id = UUID(uuidString: text) else { throw invalidArguments() }
            guard let index = session.logs.firstIndex(where: { $0.id == id }) else {
                return failure(
                    "CURSOR_EXPIRED", "Logs were cleared or the cursor was evicted. Read again without a cursor.",
                    session)
            }
            start = index + 1
            cursor = id.uuidString
        }
        var entries: [[String: Any]] = []
        var bytes = 0
        let formatter = ISO8601DateFormatter()
        // Bound payload size as well as row count. The source already bounds individual records.
        for entry in session.logs.dropFirst(start).prefix(limit) {
            guard bytes + entry.text.utf8.count <= 65_536 else { break }
            bytes += entry.text.utf8.count
            cursor = entry.id.uuidString
            entries.append([
                "id": entry.id.uuidString, "date": formatter.string(from: entry.date),
                "text": entry.text, "is_error": entry.isError,
            ])
        }
        return success([
            "session_id": session.id.uuidString, "launch_id": session.launchID.uuidString,
            "entries": entries, "next_cursor": cursor as Any? ?? NSNull(),
            "has_more": start + entries.count < session.logs.count,
        ])
    }

    private func snapshot(_ session: FlutterSession) -> [String: Any] {
        var actions: [String] = []
        if !manager.shuttingDown && !busySessions.contains(session.id) {
            if session.canRestart && session.appID != nil { actions += ["hot_reload", "hot_restart"] }
            if session.canStop { actions.append("stop_session") }
        }
        return [
            "session_id": session.id.uuidString, "launch_id": session.launchID.uuidString,
            "project": session.launchProject.map { ["id": $0.id.uuidString, "name": $0.name, "path": $0.path] } as Any?
                ?? NSNull(),
            "device": session.device.map { ["id": $0.id, "name": $0.name, "platform": $0.targetPlatform] } as Any?
                ?? NSNull(),
            "mode": session.launchProject?.launch.mode.rawValue as Any? ?? NSNull(),
            "state": session.state.rawValue, "is_alive": session.isAlive, "preparing": session.preparing,
            "error": session.error as Any? ?? NSNull(), "progress": session.progressMessage as Any? ?? NSNull(),
            "available_actions": actions,
        ]
    }

    private func success(_ value: [String: Any]) -> [String: Any] { result(value, isError: false) }
    private func failure(_ code: String, _ message: String, _ session: FlutterSession? = nil) -> [String: Any] {
        var value: [String: Any] = ["error": ["code": code, "message": message]]
        if let session { value["session"] = snapshot(session) }
        return result(value, isError: true)
    }
    private func result(_ value: [String: Any], isError: Bool) -> [String: Any] {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return [
            "content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]],
            "structuredContent": value, "isError": isError,
        ]
    }
    private func invalidArguments() -> ControlError {
        ControlError(code: "INVALID_ARGUMENTS", message: "Arguments do not match the tool schema.")
    }
}
