// swift-tools-version: 6.2
import PackageDescription

// UI module: Approachable Concurrency plus main-actor-by-default.
let uiSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "DesignSystem",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(name: "DesignSystem", resources: [.process("Resources")], swiftSettings: uiSettings),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"], swiftSettings: uiSettings),
    ]
)
