import XCTest
import Darwin
import Combine
@testable import FluttiosCore

/// Opt-in: requires fixtures from scripts/create-probes.sh and two booted iOS devices.
final class IntegrationTests: XCTestCase {
    @MainActor private func wait(_ session: FlutterSession, until condition: () -> Bool, timeout: TimeInterval = 420) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if session.state == .error || session.state == .disconnected {
                throw FluttiosError.message(session.logs.suffix(30).map { $0.text }.joined(separator: "\n"))
            }
            guard Date() < deadline else { throw FluttiosError.timeout(session.logs.suffix(10).map { $0.text }.joined(separator: "\n")) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    @MainActor func testRealFlutterTwoProjects() async throws {
        guard ProcessInfo.processInfo.environment["FLUTTIOS_INTEGRATION"] == "1" else { throw XCTSkip("Opt-in real simulator test") }
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let archive = root.appendingPathComponent(".build/integration/projects.json")
        let store = ProjectStore(file: archive)
        var a = try store.open(root.appendingPathComponent(".build/integration/Проект A"))
        var b = try store.open(root.appendingPathComponent(".build/integration/Проект B"))
        a.launch.arguments = ["--no-pub"]; b.launch.arguments = ["--no-pub"]
        let simulator = SimulatorService(); await simulator.refresh()
        let booted = simulator.devices.filter { $0.state == "Booted" }
        guard booted.count >= 2 else { throw XCTSkip("Boot two iOS simulators before running") }
        let device = booted[0], second = booted[1]
        let manager = SessionManager(simulators: simulator)
        let sa = manager.session(for: a.id), sb = manager.session(for: b.id)
        let source = root.appendingPathComponent(".build/integration/Проект A/lib/main.dart")
        let original = try String(contentsOf: source)
        defer { try? original.write(to: source, atomically: true, encoding: .utf8) }
        var sinks: Set<AnyCancellable> = []
        for (name, session) in [("a", sa), ("b", sb)] {
            session.$logs.sink { logs in
                try? logs.map { $0.text }.joined(separator: "\n").write(to: root.appendingPathComponent(".build/integration/session-" + name + ".log"), atomically: true, encoding: .utf8)
            }.store(in: &sinks)
        }
        defer { withExtendedLifetime(sinks) {} }
        do {
            print("REAL: Run A on \(device.name)")
            manager.run(project: a, device: device, globalSDK: nil)
            try await wait(sa) { sa.state == .running && sa.logs.contains { $0.text.contains("PROBE_TICK=2") } }
            store.select(b.id)
            print("REAL: Run B on same device, preserve A")
            manager.run(project: b, device: device, globalSDK: nil)
            try await wait(sb) { sb.state == .running }
            XCTAssertTrue(sa.isAlive)
            store.select(a.id); await manager.foreground(a.id); XCTAssertEqual(store.selectedID, a.id); XCTAssertTrue(sb.isAlive)
            let starts = sa.logs.filter { $0.text.contains("PROBE_INIT=0") }.count
            let bReloads = sb.logs.filter { $0.text.contains("PROBE_REASSEMBLE=") }.count
            print("REAL: Hot Reload A retains counter")
            try original.replacingOccurrences(of: "Fluttios protocol probe", with: "Fluttios reload probe").write(to: source, atomically: true, encoding: .utf8)
            sa.restart(full: false)
            try await wait(sa) { sa.state == .running && sa.logs.contains { $0.text.contains("PROBE_REASSEMBLE=") } }
            let countLine = sa.logs.last { $0.text.contains("PROBE_REASSEMBLE=") }!.text
            let retained = Int(countLine.components(separatedBy: "PROBE_REASSEMBLE=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? -1
            XCTAssertGreaterThan(retained, 0)
            XCTAssertEqual(sb.logs.filter { $0.text.contains("PROBE_REASSEMBLE=") }.count, bReloads)
            XCTAssertEqual(sa.logs.filter { $0.text.contains("PROBE_INIT=0") }.count, starts)
            print("REAL: Hot Restart A resets counter")
            sa.restart(full: true)
            try await wait(sa) { sa.state == .running && sa.logs.filter { $0.text.contains("PROBE_INIT=0") }.count > starts }
            print("REAL: foreground existing app through simctl")
            await manager.foreground(a.id); XCTAssertTrue(sa.isAlive)
            print("REAL: Dart compile error and recovery")
            try (original + "\nthis is not valid dart;\n").write(to: source, atomically: true, encoding: .utf8)
            sa.restart(full: false)
            try await wait(sa) { sa.state == .running && sa.error != nil }
            try original.write(to: source, atomically: true, encoding: .utf8)
            sa.restart(full: false); try await wait(sa) { sa.state == .running && sa.error == nil }
            print("REAL: Stop A preserves B; Run A again")
            sa.stop(); try await wait(sa) { sa.canRun }; XCTAssertTrue(sb.isAlive)
            manager.run(project: a, device: device, globalSDK: nil); try await wait(sa) { sa.state == .running }
            print("REAL: Conflict detected before replacing app")
            var conflict = a; conflict.id = UUID(); conflict.name = "Conflict"
            let sc = manager.session(for: conflict.id)
            manager.run(project: conflict, device: device, globalSDK: nil)
            let deadline = Date().addingTimeInterval(120)
            while sc.state != .error && Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
            XCTAssertEqual(sc.state, .error); XCTAssertTrue(sc.error?.contains(L10n.resolvedLanguage == .russian ? "Выберите другое устройство" : "Select another device") ?? false)
            XCTAssertFalse(sc.isAlive); XCTAssertTrue(sa.isAlive); XCTAssertTrue(sb.isAlive)
            print("REAL: B moves to second simulator after explicit Stop")
            sb.stop(); try await wait(sb) { sb.canRun }
            manager.run(project: b, device: second, globalSDK: nil); try await wait(sb) { sb.state == .running }
            XCTAssertEqual(sb.device?.id, second.id); XCTAssertTrue(sa.isAlive)
            await manager.waitForStop(); XCTAssertFalse(manager.hasActiveSessions)
            print("REAL: all owned Flutter processes stopped")
        } catch {
            print("REAL failure A:\n" + sa.logs.suffix(40).map { $0.text }.joined(separator: "\n"))
            print("REAL failure B:\n" + sb.logs.suffix(40).map { $0.text }.joined(separator: "\n"))
            await manager.waitForStop(); throw error
        }
    }
}
