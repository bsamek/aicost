// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexCost",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CostCore", targets: ["CostCore"]),
        .executable(name: "CodexCost", targets: ["CodexCost"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "CostCore", resources: [.process("Resources")]),
        .executableTarget(
            name: "CodexCost",
            dependencies: ["CostCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(name: "CostCoreTests", dependencies: ["CostCore"]),
        .testTarget(name: "AppTests", dependencies: ["CodexCost", "CostCore"]),
    ],
    swiftLanguageModes: [.v6]
)
