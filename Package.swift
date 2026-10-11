// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CodexCost",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CostCore", targets: ["CostCore"])],
    targets: [
        .target(name: "CostCore", resources: [.process("Resources")]),
        .testTarget(name: "CostCoreTests", dependencies: ["CostCore"])
    ],
    swiftLanguageModes: [.v6]
)
