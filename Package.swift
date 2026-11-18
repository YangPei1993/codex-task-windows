// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskWindows",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TaskWindows", targets: ["TaskWindows"])],
    targets: [
        .executableTarget(name: "TaskWindows", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "TaskWindowsTests", dependencies: ["TaskWindows"])
    ]
)
