import AppKit

@available(macOS 26.0, *)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dot: DotController!
    private var launcher: LauncherController!
    private let hotkey = ModifierHotkey()
    private var statusItem: NSStatusItem!
    private var dotToggleItem: NSMenuItem!
    private var openItem: NSMenuItem!
    private var settingsItem: NSMenuItem!
    private var quitItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        launcher = LauncherController()

        dot = DotController()
        dot.onClick = { [weak self] in self?.toggleFromDot() }
        dot.onDragStart = { [weak self] in self?.launcher.close() }
        dot.applySettings()

        NotificationCenter.default.addObserver(forName: AppSettings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.dot.applySettings()
        }

        hotkey.onTap = { [weak self] in
            guard let self else { return }
            if self.launcher.isVisible { self.launcher.close() } else { self.launcher.show(anchor: .mouse) }
        }
        hotkey.start()

        setupStatusItem()
        setupMainMenu()
        if CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--settings-tab") { SettingsWindowController.shared.show() }

        // 辅助功能权限：只在第一次启动时请求一次。系统不会记住「已经问过」，
        // 每调用一次就弹一次框，所以之后不再自动请求，改由 设置 → 权限 里的按钮让用户主动授权
        let d = UserDefaults.standard
        if !AXIsProcessTrusted() && !d.bool(forKey: "didPromptAccessibility") {
            d.set(true, forKey: "didPromptAccessibility")
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }

    private func toggleFromDot() {
        if launcher.isVisible { launcher.close() } else { launcher.show(anchor: .dot(dot.window.frame, dot.edge)) }
    }

    /// 状态栏菜单只留常用的：打开面板、显示/隐藏小圆点、设置、退出
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "DockDot")

        let menu = NSMenu()
        openItem = menu.addItem(withTitle: "", action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        dotToggleItem = menu.addItem(withTitle: "", action: #selector(toggleDot), keyEquivalent: "")
        dotToggleItem.target = self
        menu.addItem(.separator())
        settingsItem = menu.addItem(withTitle: "", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(.separator())
        quitItem = menu.addItem(withTitle: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
    }

    /// 打开设置时 App 会临时变成普通 App，这时菜单栏里显示这套菜单
    private func setupMainMenu() {
        let main = NSMenu()
        func sub(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            holder.submenu = m
            main.addItem(holder)
        }
        func item(_ t: String, _ a: Selector?, _ k: String, _ target: AnyObject? = nil, mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        sub("DockDot", [
            item(L("关于 DockDot", "About DockDot"), #selector(openAbout), "", self),
            .separator(),
            item(L("设置…", "Settings…"), #selector(openSettings), ",", self),
            .separator(),
            item(L("隐藏 DockDot", "Hide DockDot"), #selector(NSApplication.hide(_:)), "h"),
            item(L("退出 DockDot", "Quit DockDot"), #selector(NSApplication.terminate(_:)), "q"),
        ])
        sub(L("编辑", "Edit"), [
            item(L("撤销", "Undo"), Selector(("undo:")), "z"),
            item(L("重做", "Redo"), Selector(("redo:")), "z", mods: [.command, .shift]),
            .separator(),
            item(L("剪切", "Cut"), #selector(NSText.cut(_:)), "x"),
            item(L("拷贝", "Copy"), #selector(NSText.copy(_:)), "c"),
            item(L("粘贴", "Paste"), #selector(NSText.paste(_:)), "v"),
            item(L("全选", "Select All"), #selector(NSText.selectAll(_:)), "a"),
        ])
        sub(L("窗口", "Window"), [
            item(L("最小化", "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"),
            item(L("关闭", "Close"), #selector(NSWindow.performClose(_:)), "w"),
        ])
        NSApp.mainMenu = main
    }

    @objc private func openAbout() { SettingsWindowController.shared.show(pane: .about) }

    @objc private func openPanel() { launcher.show(anchor: .mouse) }
    @objc private func toggleDot() { AppSettings.shared.dotVisible.toggle() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
}

@available(macOS 26.0, *)
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // 每次打开菜单时按当前语言刷新文字
        openItem.title = L("打开面板", "Open Panel")
        dotToggleItem.title = dot.isVisible ? L("隐藏小圆点", "Hide Dot") : L("显示小圆点", "Show Dot")
        settingsItem.title = L("设置…", "Settings…")
        quitItem.title = L("退出 DockDot", "Quit DockDot")
    }
}
