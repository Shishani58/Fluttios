import XCTest

@testable import SimFlutDockCore

final class ParserTests: XCTestCase {
    func testFragmentedUTF8AndMultipleMessages() throws {
        var parser = MachineParser()
        let source = Data(
            "[{\"event\":\"app.log\",\"params\":{\"log\":\"Привет\"}}]\n[{\"id\":3,\"result\":true},{\"event\":\"app.started\"}]\n"
                .utf8)
        var output: [MachineOutput] = []
        for byte in source { output += parser.feed(Data([byte])) }
        XCTAssertEqual(output.count, 3)
        guard case .message(let message) = output[0] else { return XCTFail() }
        XCTAssertEqual((message["params"] as? [String: Any])?["log"] as? String, "Привет")
    }
    func testOrdinaryTextMalformedJSONAndFinalLine() {
        var parser = MachineParser()
        let output =
            parser.feed(Data("building\n[not json]\n[1,2]\n[{\"event\":\"app.stop\"}]\nlast".utf8)) + parser.finish()
        XCTAssertEqual(output.count, 5)
        guard case .text(let last) = output.last else { return XCTFail() }
        XCTAssertEqual(last, "last")
        XCTAssertTrue(parser.finish().isEmpty)
    }
    func testDartConsoleJSONRemainsOrdinaryText() {
        var parser = MachineParser(parseMessages: false)
        let output = parser.feed(Data("[{\"event\":\"app.stop\"}]\n".utf8))
        guard case .text(let text) = output.first else { return XCTFail() }
        XCTAssertEqual(text, "[{\"event\":\"app.stop\"}]")
    }
    func testUnboundedLineIsCapped() {
        var parser = MachineParser()
        XCTAssertEqual(parser.feed(Data(repeating: 65, count: 1_048_577)).count, 1)
    }
}
