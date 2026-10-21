// swift-tools-version: 5.9
// CLT-buildable SwiftPM harness for the DynamicNotch app sources.
// Compiles the same `Sources/` directory as the XcodeGen app target (project.yml) as a
// library, so compile errors can be iterated on without Xcode.app. Keep the dependency
// list in sync with `packages:` in project.yml.
import PackageDescription
// Dependency reduction (2026-10-20): Sparkle, SmoothGradient, Lottie, RichTextKit and
// CodeEditor (+ Highlightr) were replaced with first-party APIs, and sindresorhus/Defaults with
// SettingsStore (Sources/Support/SettingsStorage.swift); only mediaremote-adapter remains.

let package = Package(
    name: "DynamicNotchApp",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "DynamicNotchApp", targets: ["DynamicNotchApp"]),
        // F4: opens dynamicnotch:// command URLs (docs/automation.md). `swift run dnctl --help`
        .executable(name: "dnctl", targets: ["dnctl"]),
    ],
    dependencies: [
        // No version tags; uses unsafeFlags, so it must be a branch/revision dependency.
        .package(url: "https://github.com/ejbills/mediaremote-adapter", revision: "5b6afde3f501a3da567e23bf7f23d562938a1809"),
    ],
    targets: [
        .target(
            name: "DynamicNotchApp",
            dependencies: [
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter"),
            ],
            path: "Sources",
            // The Fan Control glue imports FanControlUI, which the harness does not link (the Xcode
            // targets compile it; every app-side use is behind `#if canImport(FanControlKit)`).
            exclude: ["FanControlGlue"],
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"]),
                // Harness-only: selects the type-check-only SwiftData fallbacks (no SwiftDataMacros in CLT).
                .define("DN_CLT_HARNESS"),
            ]
        ),
        // Unit tests: every Swift file under Tests/ (one target, so new suites such as
        // Tests/EngineTests/ are picked up without editing this file). Mirrors the Xcode target
        // `DynamicNotchAppTests` in project.yml, which compiles the same files.
        //   swift test                               # all suites
        //   swift test --filter SettingsStorage      # SettingsStore ↔ Defaults 8.2 format
        //   swift test --filter Automation           # dynamicnotch:// parsing, CommandRouter (F4)
        //   DN_SETTINGS_PLIST=<path to `defaults export com.example.dynamicnotch.DynamicNotch -` copy> swift test …
        .testTarget(
            name: "DynamicNotchAppTests",
            dependencies: ["DynamicNotchApp"],
            path: "Tests",
            exclude: ["SettingsStorageTests/Fixtures"],
            swiftSettings: [.unsafeFlags(["-swift-version", "5"]), .define("DN_CLT_HARNESS")]
        ),
        // F4: tiny CLI, Foundation/AppKit only (does not link the app sources).
        .executableTarget(
            name: "dnctl",
            path: "Tools/dnctl",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        ),
    ]
)
