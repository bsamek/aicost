// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexCost",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CostCore", targets: ["CostCore"]),
        .executable(name: "CodexCost", targets: ["CodexCost"]),
    ],
    targets: [
        .target(name: "CostCore", resources: [.process("Resources")]),
        .executableTarget(name: "CodexCost", dependencies: ["CostCore"]),
        .testTarget(name: "CostCoreTests", dependencies: ["CostCore"]),
        .testTarget(name: "AppTests", dependencies: ["CodexCost", "CostCore"]),
    ],
    swiftLanguageModes: [.v6]
)
