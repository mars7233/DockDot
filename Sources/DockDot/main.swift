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

// `DockDot --where` 只打印点击每个运行中 App 时会怎么切换（不实际切换），用于排查多屏/多桌面
if CommandLine.arguments.contains("--where") {
    let (pinned, running) = DockReader.items()
    for it in (pinned + running) where it.isRunning {
        if let app = DockReader.runningApp(for: it) { print("\(it.name): \(SpaceFocus.decide(for: app))") }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
