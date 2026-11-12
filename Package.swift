// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DockDot",
    platforms: [.macOS("26.0")],   // 液态玻璃（NSGlassEffectView）需要 macOS 26
    targets: [
        .executableTarget(name: "DockDot", path: "Sources/DockDot")
    ]
)
