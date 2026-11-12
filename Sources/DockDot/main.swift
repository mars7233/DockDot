import AppKit

// 调试参数（只在 macOS 26+ 上有意义）
if #available(macOS 26.0, *) {
    // `DockDot --dump` 只打印读到的 Dock 内容
    if CommandLine.arguments.contains("--dump") {
        let (pinned, running) = DockReader.items()
        print(L("固定在 Dock 上 (\(pinned.count)):", "Pinned in Dock (\(pinned.count)):"))
        for i in pinned { print("  \(i.isRunning ? "●" : " ") \(i.name)  \(i.url.path)") }
        print(L("其他正在运行 (\(running.count)):", "Other running (\(running.count)):"))
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

// `open DockDot.app --args --ax-report <文件>`：在 App 自己的进程里检查辅助功能权限，结果写进文件
if let i = CommandLine.arguments.firstIndex(of: "--ax-report"), i + 1 < CommandLine.arguments.count {
    var out = "AXIsProcessTrusted=\(AXIsProcessTrusted())\n"
    if let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
        var v: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(finder.processIdentifier), kAXWindowsAttribute as CFString, &v)
        out += "readFinderWindows=\(err.rawValue) (0 = 能读到，-25211 = 没有权限)\n"
    }
    out += "inputMonitoring(CGPreflightListenEventAccess)=\(CGPreflightListenEventAccess())\n"
    out += "bundle=\(Bundle.main.bundlePath)\n"
    try? out.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
    exit(0)
}

// `open DockDot.app --args --open-app <名字> <日志文件>`：走和点图标完全一样的打开流程，并把每一步写进日志
if #available(macOS 26.0, *), let i = CommandLine.arguments.firstIndex(of: "--open-app"), i + 2 < CommandLine.arguments.count {
    let name = CommandLine.arguments[i + 1].lowercased()
    let logPath = CommandLine.arguments[i + 2]
    SpaceFocus.debugLog = { line in
        let old = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        try? (old + line + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
    }
    let (pinned, running) = DockReader.items()
    if let item = (pinned + running).first(where: { $0.name.lowercased().contains(name) }) {
        SpaceFocus.debugLog?("open \(item.name)")
        DockReader.open(item)
    } else {
        SpaceFocus.debugLog?("not found: \(name)")
    }
    RunLoop.main.run(until: Date().addingTimeInterval(3))
    exit(0)
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
