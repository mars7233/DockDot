import AppKit

// 调试参数（只在 macOS 26+ 上有意义）
if #available(macOS 26.0, *) {
    // `DockDot --dump` 只打印读到的 Dock 内容
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
}

// `DockDot --env-check` 只打印环境检测结果
if CommandLine.arguments.contains("--env-check") {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    print("macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
    print("bundle: \(Bundle.main.bundlePath)")
    print("result: \(EnvironmentCheck.problem().map { "\($0)" } ?? "OK")")
    exit(0)
}

let app = NSApplication.shared

// 先做环境检测：系统太旧、或直接在安装盘里打开，都给出提示并退出
if let problem = EnvironmentCheck.problem() {
    EnvironmentCheck.handle(problem)
}

var appDelegate: NSObject?
if #available(macOS 26.0, *) {
    let d = AppDelegate()
    appDelegate = d
    app.delegate = d
    app.setActivationPolicy(.accessory)
    app.run()
}
