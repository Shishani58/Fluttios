// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SimFlutDock", platforms: [.macOS(.v14)], products: [
    .executable(name: "SimFlutDock", targets: ["SimFlutDock"]),
    .executable(name: "SimFlutDockHelper", targets: ["SimFlutDockHelper"])
], targets: [
    .target(name: "SimFlutDockCore"),
    .executableTarget(name: "SimFlutDock", dependencies: ["SimFlutDockCore"]),
    .executableTarget(name: "SimFlutDockHelper"),
    .testTarget(name: "SimFlutDockCoreTests", dependencies: ["SimFlutDockCore"])
])
