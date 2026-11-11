// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacJanitor",
    platforms: [.macOS(.v13)],
    targets: [
        // Cleanup rules, the run report, and the paths both front-ends share.
        .target(name: "JanitorCore", path: "Sources/JanitorCore"),
        // `janitor run`, shared by the CLI and the app's headless mode.
        .target(name: "JanitorCLI", dependencies: ["JanitorCore"], path: "Sources/JanitorCLI"),
        // The CLI, for developers; the app bundle runs its own executable instead.
        .executableTarget(
            name: "janitor",
            dependencies: ["JanitorCLI"],
            path: "Sources/janitor"
        ),
        // The menu-bar app; with `run ...` arguments it is the CLI.
        .executableTarget(
            name: "MacJanitor",
            dependencies: ["JanitorCore", "JanitorCLI"],
            path: "Sources/MacJanitor"
        ),
        .testTarget(
            name: "JanitorCoreTests",
            dependencies: ["JanitorCore", "JanitorCLI"],
            path: "Tests/JanitorCoreTests"
        ),
    ]
)
