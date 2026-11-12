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
        if CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--settings-tab") { SettingsWindowController.shared.show() }

        // 快捷键需要辅助功能权限；没授权时只弹一次系统提示，小圆点照常可用
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
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
