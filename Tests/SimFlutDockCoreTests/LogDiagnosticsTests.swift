import XCTest

@testable import SimFlutDockCore

final class LogDiagnosticsTests: XCTestCase {
    func testErrorFilterKeepsStdoutExceptionDetailsAndCombinesSearch() {
        let entries = [
            LogEntry("ordinary output"), LogEntry("══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞══"),
            LogEntry("A RenderFlex overflowed by 42 pixels"),
            LogEntry("#0 Widget.build (package:demo/main.dart:12:4)"),
            LogEntry("════════════════════"), LogEntry("another ordinary line"),
            LogEntry("compiler error", isError: true),
        ]
        XCTAssertEqual(
            LogDiagnostics.filtered(entries, query: "", errorsOnly: true).map(\.text),
            Array(entries[1...4]).map(\.text) + ["compiler error"])
        XCTAssertEqual(
            LogDiagnostics.filtered(entries, query: "OVERFLOWED", errorsOnly: true).map(\.text),
            ["A RenderFlex overflowed by 42 pixels"])
    }

    func testStackReferencesResolvePackageConfigRelativeRootsAndExactSourcePositions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: folder) }
        let dartTool = folder.appendingPathComponent(".dart_tool")
        try FileManager.default.createDirectory(at: dartTool, withIntermediateDirectories: true)
        try #"{"packages":[{"name":"demo","rootUri":"../","packageUri":"lib/"}]}"#
            .write(to: dartTool.appendingPathComponent("package_config.json"), atomically: true, encoding: .utf8)
        let text =
            "#0 build (package:demo/экран.dart:12:4)\nlib/main.dart:7\nhttps://host/index.html:4:5\n/etc/private.dart:3:1\nlib/../../escape.dart:1:1"
        let locations = LogSourceLocation.locations(
            in: text, projectPath: folder.path,
            packageRoots: LogSourceLocation.packageRoots(projectPath: folder.path))
        XCTAssertEqual(locations.map(\.file.path), [folder.path + "/lib/экран.dart", folder.path + "/lib/main.dart"])
        XCTAssertEqual(locations.map(\.line), [12, 7])
        XCTAssertEqual(locations.map(\.column), [4, 1])
        XCTAssertEqual((text as NSString).substring(with: locations[0].range), "package:demo/экран.dart:12:4")
    }

    func testErrorReportIncludesContextAroundLatestErrorInsteadOfUnrelatedTail() {
        let entries = (0..<150).map { LogEntry("line \($0)", isError: $0 == 50 || $0 == 100) }
        let report = LogDiagnostics.reportEntries(entries)
        XCTAssertEqual(report.first?.text, "line 60")
        XCTAssertEqual(report.last?.text, "line 120")
        XCTAssertTrue(report.contains { $0.text == "line 100" })

        for (header, message, closing) in [
            (
                "══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞══", "A RenderFlex overflowed by 42 pixels",
                "════════════════════"
            ),
            ("Unhandled exception:", "Bad state: connection failed", ""),
        ] {
            let longException =
                [LogEntry(header), LogEntry(message)]
                + (0..<150).map { LogEntry("#\($0) build (lib/main.dart:12:4)") }
                + (closing.isEmpty ? [] : [LogEntry(closing)])
            let exceptionReport = LogDiagnostics.reportEntries(longException)
            XCTAssertLessThanOrEqual(exceptionReport.count, 80)
            XCTAssertTrue(exceptionReport.contains { $0.text == message })
            XCTAssertEqual(exceptionReport.last?.text, closing.isEmpty ? "#149 build (lib/main.dart:12:4)" : closing)
            let laterError = LogDiagnostics.reportEntries(
                longException + [LogEntry("new unrelated error", isError: true)])
            XCTAssertFalse(laterError.contains { $0.text == header })
        }
    }
}
