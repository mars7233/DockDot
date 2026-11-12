import AppKit

// `DockDot --dump` 只打印读到的 Dock 内容，用于调试
if CommandLine.arguments.contains("--dump") {
    let (pinned, running) = DockReader.items()
    print("固定在 Dock 上 (\(pinned.count)):")
    for i in pinned { print("  \(i.isRunning ? "●" : " ") \(i.name)  \(i.url.path)") }
    print("其他正在运行 (\(running.count)):")
    for i in running { print("  ● \(i.name)  \(i.url.path)") }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
