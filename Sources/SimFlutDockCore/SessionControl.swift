import AppKit
import CoreFoundation
import Foundation

enum AndroidDeviceCommand {
    static func deepLinkArguments(deviceID: String, url: String) throws -> [String] {
        let validated = try SavedDeepLink.validatedURL(url)
        // adb shell joins its arguments into a remote shell command; quote the URL there too.
        let quoted = "'" + validated.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return ["-s", deviceID, "shell", "am", "start", "-W", "-a", "android.intent.action.VIEW", "-d", quoted]
    }
}

/// Panel and MCP operations share explicit project/device session ownership.
@MainActor public final class SessionControl {
    private struct ControlError: Error {
        let code: String
        let message: String
    }
    private final class Command {
        let fingerprint: [String]
        var task: Task<[String: Any], Never>!
        var completed = false
        var artifact: URL?
        deinit { if let artifact { try? FileManager.default.removeItem(at: artifact.deletingLastPathComponent()) } }
        init(_ fingerprint: [String]) { self.fingerprint = fingerprint }
    }
    private let manager: SessionManager
    private let store: ProjectStore?
    private let globalSDK: () -> String?
    private var commands: [String: Command] = [:]
    private var commandOrder: [String] = []
    private var busySessions: Set<UUID> = []

    public init(manager: SessionManager, store: ProjectStore? = nil, globalSDK: @escaping () -> String? = { nil }) {
        self.manager = manager
        self.store = store
        self.globalSDK = globalSDK
    }

    public func handle(_ data: Data) async -> Data {
        var result: [String: Any]
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
        // Keep images on disk in the retry cache, rather than retaining base64 in every command task.
        if result["isError"] as? Bool == false,
            let value = result["structuredContent"] as? [String: Any],
            let path = value["image_path"] as? String,
            let image = try? Data(contentsOf: URL(fileURLWithPath: path)), image.count <= 1_000_000
        {
            var content = result["content"] as? [[String: Any]] ?? []
            content.append(["type": "image", "mimeType": "image/jpeg", "data": image.base64EncodedString()])
            result["content"] = content
        }
        // Every result is constructed from JSON primitives.
        return try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    private func call(_ tool: String, _ args: [String: Any]) async throws -> [String: Any] {
        switch tool {
        case "list_projects":
            guard args.isEmpty else { throw invalidArguments() }
            let projects = (store?.projects ?? []).map { project -> [String: Any] in
                [
                    "id": project.id.uuidString, "name": project.name, "path": project.path,
                    "configuration": [
                        "mode": project.launch.mode.rawValue, "entrypoint": project.launch.entrypoint,
                        "scheme": project.launch.scheme, "build_configuration": project.launch.buildConfiguration,
                    ],
                    "deep_links": project.deepLinks.map { ["name": $0.name, "url": $0.url] },
                ]
            }
            return success(["projects": projects])
        case "list_devices":
            guard Set(args.keys) == ["project_id"] else { throw invalidArguments() }
            let project = try findProject(args)
            while manager.simulators.refreshing { try? await Task.sleep(nanoseconds: 20_000_000) }
            await manager.simulators.refresh(project: project, globalSDK: globalSDK())
            return success([
                "devices": manager.simulators.devices.filter {
                    manager.simulators.currentDeviceIDs.contains($0.id) && $0.isAvailable
                }.map { ["id": $0.id, "name": $0.name, "platform": $0.targetPlatform, "state": $0.state] },
                "discovery_error": manager.simulators.error as Any? ?? NSNull(),
            ])
        case "start_session", "rerun_session", "open_deep_link", "take_screenshot":
            return try await extendedCommand(tool, args)
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

    private func findProject(_ args: [String: Any]) throws -> Project {
        guard let text = args["project_id"] as? String, let id = UUID(uuidString: text) else {
            throw invalidArguments()
        }
        guard let project = store?.projects.first(where: { $0.id == id }) else {
            throw ControlError(
                code: "PROJECT_NOT_FOUND", message: "List saved projects and use an explicit project_id.")
        }
        return project
    }

    private func extendedCommand(_ tool: String, _ args: [String: Any]) async throws -> [String: Any] {
        let starting = tool == "start_session"
        var keys: Set<String> =
            starting ? ["project_id", "device_id", "request_id"] : ["session_id", "launch_id", "request_id"]
        if tool == "open_deep_link" { keys.insert("url") }
        guard Set(args.keys) == keys, let requestID = args["request_id"] as? String,
            !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, requestID.utf8.count <= 128
        else { throw invalidArguments() }
        var fingerprint = [tool]
        for key in keys.sorted() where key != "request_id" {
            guard let value = args[key] as? String, !value.isEmpty, value.utf8.count <= 8192,
                value.rangeOfCharacter(from: .controlCharacters) == nil
            else { throw invalidArguments() }
            if ["project_id", "session_id", "launch_id"].contains(key) {
                guard let id = UUID(uuidString: value) else { throw invalidArguments() }
                fingerprint.append(id.uuidString)
            } else {
                fingerprint.append(value)
            }
        }
        if let previous = commands[requestID] {
            guard previous.fingerprint == fingerprint else {
                throw ControlError(
                    code: "REQUEST_ID_CONFLICT", message: "Use this request_id only for the original command.")
            }
            return await previous.task.value
        }
        guard !manager.shuttingDown else { return failure("SHUTTING_DOWN", "Fluttios is shutting down.") }
        let project: Project
        let session: FlutterSession
        let launch: UUID?
        if starting {
            project = try findProject(args)
            guard
                manager.simulators.devices.contains(where: {
                    $0.id == args["device_id"] as? String && $0.isAvailable
                        && manager.simulators.currentDeviceIDs.contains($0.id)
                })
            else { return failure("DEVICE_UNAVAILABLE", "List devices for this project before starting.") }
            session = manager.session(for: project.id, deviceID: args["device_id"] as! String)
            launch = nil
            guard session.canRun else {
                return failure(
                    "ACTION_UNAVAILABLE", "This session already has work. Inspect it before rerunning.", session)
            }
        } else {
            session = try findSession(args)
            launch = UUID(uuidString: args["launch_id"] as! String)!
            guard session.launchID == launch else {
                return failure("STALE_LAUNCH", "Read the session's current launch.", session)
            }
            guard let saved = store?.projects.first(where: { $0.id == session.projectID }) ?? session.launchProject
            else {
                return failure("PROJECT_NOT_FOUND", "The launch project is unavailable.", session)
            }
            project = saved
            if tool == "rerun_session" {
                guard session.canRerun else {
                    return failure("ACTION_UNAVAILABLE", "Rerun is unavailable in this state.", session)
                }
            } else {
                guard session.state == .running, let device = session.device,
                    device.isIOSSimulator || device.targetPlatform.hasPrefix("android")
                else {
                    return failure(
                        "ACTION_UNAVAILABLE", "This action requires a running iOS Simulator or Android session.",
                        session)
                }
            }
        }
        let key = SessionKey(
            projectID: project.id, deviceID: starting ? args["device_id"] as! String : session.device!.id)
        guard !busySessions.contains(session.id), !manager.rerunningIDs.contains(key),
            !manager.foregroundIDs.contains(key)
        else { return failure("BUSY", "Another operation is in progress.", session) }
        if tool == "open_deep_link" { _ = try SavedDeepLink.validatedURL(args["url"] as! String) }
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
        command.task = Task { [self] in
            defer {
                busySessions.remove(session.id)
                command.completed = true
            }
            do {
                if starting {
                    while manager.simulators.refreshing { try? await Task.sleep(nanoseconds: 20_000_000) }
                    await manager.simulators.refresh(project: project, globalSDK: globalSDK())
                    guard
                        let device = manager.simulators.devices.first(where: {
                            $0.id == key.deviceID && $0.isAvailable
                                && manager.simulators.currentDeviceIDs.contains($0.id)
                        })
                    else { return failure("DEVICE_UNAVAILABLE", "Device not discovered. List devices again.", session) }
                    guard session.canRun, !manager.shuttingDown, !manager.rerunningIDs.contains(key),
                        !manager.foregroundIDs.contains(key), manager.sessions[key] === session
                    else {
                        return failure("BUSY", "The session changed during discovery.", session)
                    }
                    _ = try project.launch.validatedArguments(for: device)
                    manager.run(project: project, device: device, globalSDK: globalSDK())
                    return success(["status": "started", "request_id": requestID, "session": snapshot(session)])
                }
                guard session.launchID == launch, let device = session.device else {
                    return failure("STALE_LAUNCH", "The launch changed before execution.", session)
                }
                if tool == "rerun_session" {
                    manager.rerun(project: project, device: device, globalSDK: globalSDK())
                    let deadline = Date().addingTimeInterval(25)
                    while session.launchID == launch && manager.rerunningIDs.contains(key) && Date() < deadline {
                        try? await Task.sleep(nanoseconds: 20_000_000)
                    }
                    guard session.launchID != launch else {
                        return failure(
                            "COMMAND_TIMEOUT",
                            "Rerun has not started. Inspect the session before taking another action.", session)
                    }
                    return success(["status": "started", "request_id": requestID, "session": snapshot(session)])
                }
                var target = device
                if device.isIOSSimulator { target = try await manager.simulators.currentSimulator(id: device.id) }
                guard session.launchID == launch, session.state == .running else {
                    return failure("STALE_LAUNCH", "The launch changed before execution.", session)
                }
                if tool == "open_deep_link" {
                    let url = try SavedDeepLink.validatedURL(args["url"] as! String)
                    if target.isIOSSimulator {
                        try await manager.simulators.openDeepLink(url, device: target)
                    } else {
                        let response = try await ToolRunner.run(
                            try adb(), AndroidDeviceCommand.deepLinkArguments(deviceID: target.id, url: url),
                            timeout: 20
                        ).checked()
                        if response.text.range(
                            of: #"(?im)^\s*(?:error:|exception|status:\s*(?:timeout|error))"#,
                            options: .regularExpression) != nil
                        {
                            throw SimFlutDockError.message(response.text)
                        }
                    }
                } else {
                    let image = try await screenshot(target)
                    command.artifact = image
                    guard session.launchID == launch else {
                        return failure("STALE_LAUNCH", "The launch changed while capturing.", session)
                    }
                    return success([
                        "status": "completed", "request_id": requestID, "session": snapshot(session),
                        "image_path": image.path, "mime_type": "image/jpeg",
                    ])
                }
                guard session.launchID == launch else {
                    return failure("STALE_LAUNCH", "The launch changed during execution.", session)
                }
                return success(["status": "completed", "request_id": requestID, "session": snapshot(session)])
            } catch {
                return failure("COMMAND_FAILED", error.localizedDescription, session)
            }
        }
        return await command.task.value
    }

    private func adb() throws -> String {
        let env = FlutterSDKResolver.environment()
        let roots = [
            env["ANDROID_SDK_ROOT"], env["ANDROID_HOME"],
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk").path,
        ].compactMap { $0 }
        let candidates =
            roots.map { $0 + "/platform-tools/adb" }
            + (env["PATH"] ?? "").split(separator: ":").map { String($0) + "/adb" }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw SimFlutDockError.message("Android platform-tools (adb) not found.")
        }
        return executable
    }

    private func screenshot(_ device: SimulatorDevice) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fluttios-capture-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: directory) } }
        let file = directory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        let data: Data
        if device.isIOSSimulator {
            guard device.state == "Booted" else { throw SimFlutDockError.message("The simulator is not booted.") }
            _ = try await ToolRunner.run(
                "/usr/bin/xcrun", ["simctl", "io", device.id, "screenshot", "--type=png", file.path], timeout: 20
            ).checked()
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 8_000_000 else { throw SimFlutDockError.message("Screenshot exceeds 8 MB.") }
            data = try Data(contentsOf: file)
        } else {
            data = try await ToolRunner.run(try adb(), ["-s", device.id, "exec-out", "screencap", "-p"], timeout: 20)
                .checked().stdout
        }
        guard let source = NSBitmapImageRep(data: data), source.pixelsWide > 0, source.pixelsHigh > 0 else {
            throw SimFlutDockError.message("The device did not return a valid screenshot.")
        }
        let scale = min(1, 1600 / Double(max(source.pixelsWide, source.pixelsHigh)))
        let width = max(1, Int(Double(source.pixelsWide) * scale))
        let height = max(1, Int(Double(source.pixelsHigh) * scale))
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw SimFlutDockError.message("Could not prepare screenshot.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.65]),
            jpeg.count <= 1_000_000
        else {
            throw SimFlutDockError.message("Screenshot exceeds the 1 MB MCP image limit.")
        }
        let output = file.deletingPathExtension().appendingPathExtension("jpg")
        try jpeg.write(to: output, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        retained = true
        return output
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
            let key = session.device.map { SessionKey(projectID: session.projectID, deviceID: $0.id) }
            if session.canRerun, let key, !manager.rerunningIDs.contains(key), !manager.foregroundIDs.contains(key) {
                actions.append("rerun_session")
            }
            if session.state == .running, let device = session.device,
                device.isIOSSimulator || device.targetPlatform.hasPrefix("android")
            {
                actions += ["open_deep_link", "take_screenshot"]
            }
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
