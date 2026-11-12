// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DockDot",
    platforms: [.macOS(.v11)],   // 能在 macOS 11+ 启动并给出提示；液态玻璃部分只在 macOS 26+ 运行
    targets: [
        .executableTarget(name: "DockDot", path: "Sources/DockDot")
    ]
)
