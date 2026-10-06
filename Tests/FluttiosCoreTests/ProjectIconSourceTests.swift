import XCTest
@testable import FluttiosCore

final class ProjectIconSourceTests: XCTestCase {
    private func withProject(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func write(_ text: String, to path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testCatalogUsesLargestExistingDefaultIcon() throws {
        try withProject { root in
            let catalog = "ios/Runner/Assets.xcassets/AppIcon.appiconset/"
            try write(#"{"images":[{"filename":"small.png","size":"60x60","scale":"2x"},{"filename":"large.png","size":"1024x1024","scale":"1x"},{"filename":"dark.png","size":"1024x1024","appearances":[{"appearance":"luminosity","value":"dark"}]},{"filename":"missing.png","size":"2048x2048"}]}"#, to: catalog + "Contents.json", in: root)
            for name in ["small.png", "large.png", "dark.png"] {
                try write("fixture", to: catalog + name, in: root)
            }
            XCTAssertEqual(ProjectIconSource.candidates(projectPath: root.path).map(\.lastPathComponent), ["large.png", "small.png"])
        }
    }

    func testInvalidIOSCatalogFallsBackToOtherPlatforms() throws {
        try withProject { root in
            try write("invalid", to: "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json", in: root)
            let mac = "macos/Runner/Assets.xcassets/AppIcon.appiconset/"
            try write(#"{"images":[{"filename":"mac.png","size":"128x128"}]}"#, to: mac + "Contents.json", in: root)
            try write("fixture", to: mac + "mac.png", in: root)
            try write("fixture", to: "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", in: root)
            try write("fixture", to: "web/icons/Icon-512.png", in: root)
            XCTAssertEqual(ProjectIconSource.candidates(projectPath: root.path).map(\.lastPathComponent), ["mac.png", "ic_launcher.png", "Icon-512.png"])
        }
    }

    func testMissingProjectAndUnsafeCatalogFilenamesHaveNoCandidates() throws {
        try withProject { root in
            XCTAssertTrue(ProjectIconSource.candidates(projectPath: root.appendingPathComponent("missing").path).isEmpty)
            let catalog = "ios/Runner/Assets.xcassets/AppIcon.appiconset/"
            try write("fixture", to: "ios/Runner/Assets.xcassets/outside.png", in: root)
            try write(#"{"images":[{"filename":"../outside.png"},{"filename":"/tmp/icon.png"},{"filename":".."},{"filename":""}]}"#, to: catalog + "Contents.json", in: root)
            XCTAssertTrue(ProjectIconSource.candidates(projectPath: root.path).isEmpty)
        }
    }
}
