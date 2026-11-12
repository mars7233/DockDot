import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dot: DotController!
    private var launcher: LauncherController!
    private let hotkey = ModifierHotkey()
    private var statusItem: NSStatusItem!
    private var dotToggleItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        launcher = LauncherController()

        dot = DotController()
        dot.onClick = { [weak self] in self?.toggleFromDot() }
        dot.onDragStart = { [weak self] in self?.launcher.close() }
        if !UserDefaults.standard.bool(forKey: "dotHidden") { dot.show() }

        hotkey.onPress = { [weak self] in self?.launcher.show(anchor: .mouse) }
        hotkey.onRelease = { [weak self] in self?.launcher.hotkeyReleased() }
        hotkey.onCancel = { [weak self] in self?.launcher.close() }
        hotkey.start()

        setupStatusItem()

        // 快捷键需要辅助功能权限；没授权时只弹一次系统提示，小圆点照常可用
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func toggleFromDot() {
        if launcher.isVisible { launcher.close() } else { launcher.show(anchor: .dot(dot.window.frame, dot.edge)) }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "DockDot")

        let menu = NSMenu()
        menu.addItem(withTitle: "打开面板", action: #selector(openPanel), keyEquivalent: "").target = self
        dotToggleItem = menu.addItem(withTitle: "", action: #selector(toggleDot), keyEquivalent: "")
        dotToggleItem.target = self
        menu.addItem(.separator())
        loginItem = menu.addItem(withTitle: "开机自动启动", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(withTitle: "辅助功能权限…（⌥⌘ 快捷键需要）", action: #selector(openAXSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "按住 ⌥⌘ 呼出，移到图标上松开即打开", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 DockDot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func openPanel() { launcher.show(anchor: .mouse) }

    @objc private func toggleDot() {
        if dot.isVisible { dot.hide() } else { dot.show() }
        UserDefaults.standard.set(!dot.isVisible, forKey: "dotHidden")
    }

    @objc private func toggleLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister() } else { try s.register() }
        } catch {
            NSLog("DockDot: 设置开机启动失败: \(error)")
        }
    }

    @objc private func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        dotToggleItem.title = dot.isVisible ? "隐藏小圆点" : "显示小圆点"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
