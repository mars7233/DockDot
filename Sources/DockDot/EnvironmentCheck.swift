import AppKit

/// 启动前的环境检测。这个文件不能用 macOS 26 才有的 API：它要在旧系统上也能跑，才能给出提示。
enum EnvironmentProblem {
    case osTooOld(current: String)
    case notInstalled          // 直接在安装盘（DMG）里或被系统放到临时位置运行
}

enum EnvironmentCheck {
    static let minimumMajor = 26

    /// 测试用：--simulate-old-macos / --simulate-dmg 可以在正常的电脑上模拟这两种情况
    static func problem() -> EnvironmentProblem? {
        let args = CommandLine.arguments
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if args.contains("--simulate-old-macos") || v.majorVersion < minimumMajor {
            let current = args.contains("--simulate-old-macos") ? "15.6" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            return .osTooOld(current: current)
        }
        let path = Bundle.main.bundlePath
        if args.contains("--simulate-dmg") || path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") {
            return .notInstalled
        }
        return nil
    }

    /// 弹出提示；不能继续运行时直接退出进程
    static func handle(_ problem: EnvironmentProblem) -> Never {
        NSApp.setActivationPolicy(.regular)   // 让提示框带图标、出现在最前面
        NSApp.activate(ignoringOtherApps: true)
        switch problem {
        case let .osTooOld(current):
            let a = NSAlert()
            a.alertStyle = .critical
            a.messageText = "DockDot 无法在这台 Mac 上运行"
            a.informativeText = """
            DockDot 需要 macOS \(minimumMajor)（Tahoe）或更高版本：它的液态玻璃效果是 macOS \(minimumMajor) 才有的系统功能。

            这台 Mac 的系统是 macOS \(current)。升级系统后就可以使用：系统设置 → 通用 → 软件更新。
            """
            a.addButton(withTitle: "打开软件更新")
            a.addButton(withTitle: "退出")
            a.window.level = .floating   // 浮在最前，开着台前调度时也不会被收到侧边
            if a.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
            }
            exit(0)

        case .notInstalled:
            let a = NSAlert()
            a.messageText = "请先把 DockDot 放进「应用程序」文件夹"
            a.informativeText = """
            现在 DockDot 是直接从安装盘里打开的。这样运行时，macOS 会把它放在一个临时位置，辅助功能权限（⌥⌘ 快捷键需要）和开机自动启动都会失效。

            可以让 DockDot 自己移过去并重新打开，也可以退出后手动把它拖到「应用程序」文件夹。
            """
            a.addButton(withTitle: "移到「应用程序」并打开")
            a.addButton(withTitle: "退出")
            a.window.level = .floating
            if a.runModal() == .alertFirstButtonReturn {
                moveToApplicationsAndRelaunch()
            }
            exit(0)
        }
    }

    private static func moveToApplicationsAndRelaunch() {
        let fm = FileManager.default
        let dest = URL(fileURLWithPath: "/Applications/DockDot.app")
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }   // 替换旧版本
            try fm.copyItem(at: Bundle.main.bundleURL, to: dest)
            // 复制出来的 App 会带着「从网上下载」的标记，再打开时又会被放到临时位置；
            // 用户已经同意打开过它，这里去掉这个标记
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            p.arguments = ["-dr", "com.apple.quarantine", dest.path]
            try? p.run()
            p.waitUntilExit()
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.createsNewApplicationInstance = true
            let done = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: dest, configuration: cfg) { _, _ in done.signal() }
            _ = done.wait(timeout: .now() + 5)
        } catch {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "没能自动移过去"
            a.informativeText = "\(error.localizedDescription)\n\n请退出后，在安装盘窗口里把 DockDot 拖到「应用程序」文件夹，再从「应用程序」里打开。"
            a.addButton(withTitle: "好")
            a.runModal()
        }
    }
}
