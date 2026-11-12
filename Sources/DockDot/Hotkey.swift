import AppKit

/// 单独按一下 ⌥⌘（按下再松开，中间没按别的键、没点鼠标）触发 onTap。
/// ⌥⌘D、⌥⌘Space、⌥⌘Esc、⌥⌘ 点击/拖动 等组合都不会误触发。
/// 全局监听需要「辅助功能」权限。
@available(macOS 26.0, *)
final class ModifierHotkey {
    var onTap: (() -> Void)?

    private let combo: NSEvent.ModifierFlags = [.command, .option]
    private let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
    private let maxHold: TimeInterval = 0.8
    private var armedAt: Date?
    private var prev: NSEvent.ModifierFlags = []
    private var monitors: [Any] = []

    private var armedCount: UInt32 = 0

    func start() {
        let add: (Any?) -> Void = { if let m = $0 { self.monitors.append(m) } }
        add(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] in self?.flags($0) })
        add(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.flags(e); return e })
        // 有辅助功能权限时，直接监听按键/点击来取消；没权限时靠下面的计数器兜底
        let others: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        add(NSEvent.addGlobalMonitorForEvents(matching: others) { [weak self] _ in self?.cancelled = true })
        add(NSEvent.addLocalMonitorForEvents(matching: others) { [weak self] e in self?.cancelled = true; return e })
    }

    private var cancelled = false

    /// 系统全局的按键 + 鼠标点击计数（不需要权限）。按住 ⌥⌘ 期间只要它变了，就说明是组合键或 ⌥⌘ 点击
    private func inputCount() -> UInt32 {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        return types.reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }

    private func flags(_ e: NSEvent) {
        let f = e.modifierFlags.intersection(relevant)
        defer { prev = f }
        if f == combo {
            // 只在从「⌥⌘ 的子集」按进来时才算，避免 ⌥⌘⇧ 松开 ⇧ 后误触发
            if combo.isSuperset(of: prev) && prev != combo {
                armedAt = Date()
                armedCount = inputCount()
                cancelled = false
            }
            return
        }
        if let t = armedAt, prev == combo, combo.isSuperset(of: f) {
            armedAt = nil
            guard Date().timeIntervalSince(t) <= maxHold else { return }
            // 系统计数器偶尔比修饰键事件晚一点更新，稍等 80ms 再核对
            let expected = armedCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, !self.cancelled, self.inputCount() == expected else { return }
                self.onTap?()
            }
            return
        }
        armedAt = nil
    }
}
