// swift-tools-version: 6.2
import PackageDescription

// Release engineering. `ReleaseKit` is the pure logic, test-first: the order to
// sign a bundle in, the designated requirement, the version rules, the appcast and
// its notes, and the licence notices. `release-kit` is the command the scripts beside
// this file call, reading files and running nothing. Shipped with nothing.
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "ReleaseTools",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ReleaseKit", targets: ["ReleaseKit"]),
        .executable(name: "release-kit", targets: ["release-kit"]),
    ],
    targets: [
        .target(name: "ReleaseKit", swiftSettings: approachableConcurrency),
        .executableTarget(name: "release-kit", dependencies: ["ReleaseKit"], swiftSettings: approachableConcurrency),
        .testTarget(name: "ReleaseKitTests", dependencies: ["ReleaseKit"], swiftSettings: approachableConcurrency),
    ]
)
