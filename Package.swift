// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Fluttios", platforms: [.macOS(.v14)], products: [
    .executable(name: "Fluttios", targets: ["Fluttios"]),
    .executable(name: "FluttiosHelper", targets: ["FluttiosHelper"])
], targets: [
    .target(name: "FluttiosCore"),
    .executableTarget(name: "Fluttios", dependencies: ["FluttiosCore"]),
    .executableTarget(name: "FluttiosHelper"),
    .testTarget(name: "FluttiosCoreTests", dependencies: ["FluttiosCore"])
])
