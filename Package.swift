// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DockDot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DockDot", path: "Sources/DockDot")
    ]
)
