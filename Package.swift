// swift-tools-version: 6.3
//
// Soniqle — a secure-by-construction SQL SELECT compiler.
//
// Toolchain posture (see ADRs/0012-swift-6.3-baseline.md):
//   * Language mode v6 — full data-race checking.
//   * defaultIsolation(nil) — this is a pure value library; every declaration is
//     `nonisolated` and every public type is `Sendable`. Nothing touches a global actor.
//   * strictMemorySafety() — the implementation contains no `unsafe` constructs; the
//     setting turns any accidental introduction into a compile error.
//   * A handful of upcoming-feature flags that Soniqle already complies with, so the
//     jump to a future language mode is a non-event.
//
// Warnings-as-errors is deliberately NOT set via `.unsafeFlags` here (that would make the

import PackageDescription

let strictSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
    .strictMemorySafety(),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "Soniqle",
    products: [
        .library(name: "Soniqle", targets: ["Soniqle"]),
    ],
    targets: [
        .target(
            name: "Soniqle",
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "SoniqleTests",
            dependencies: ["Soniqle"],
            swiftSettings: strictSwiftSettings
        ),
    ]
)
