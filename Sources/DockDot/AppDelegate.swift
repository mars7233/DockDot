import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dot: DotController!
    private var launcher: LauncherController!
    private let hotkey = ModifierHotkey()
    private var statusItem: NSStatusItem!
    private var dotToggleItem: NSMenuItem!

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
        if CommandLine.arguments.contains("--settings") { SettingsWindowController.shared.show() }

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
        menu.addItem(withTitle: "打开面板", action: #selector(openPanel), keyEquivalent: "").target = self
        dotToggleItem = menu.addItem(withTitle: "", action: #selector(toggleDot), keyEquivalent: "")
        dotToggleItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 DockDot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func openPanel() { launcher.show(anchor: .mouse) }
    @objc private func toggleDot() { AppSettings.shared.dotVisible.toggle() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        dotToggleItem.title = dot.isVisible ? "隐藏小圆点" : "显示小圆点"
    }
}
