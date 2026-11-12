import AppKit

/// 按住 ⌥⌘（只按这两个键）约 0.2 秒触发，松开时回调。
/// 期间如果按了别的键（比如 ⌥⌘Esc、⌥⌘D 这类系统快捷键），就当作没触发。
/// 全局监听需要「辅助功能」权限。
final class ModifierHotkey {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    private let combo: NSEvent.ModifierFlags = [.command, .option]
    private let delay: TimeInterval = 0.2
    private var pending: DispatchWorkItem?
    private var active = false
    private var monitors: [Any] = []

    func start() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] in self?.flags($0) }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in self?.otherKey() }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in self?.flags(e); return e }) { monitors.append(m) }
    }

    private func flags(_ e: NSEvent) {
        let f = e.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        if f == combo {
            guard !active, pending == nil else { return }
            let w = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pending = nil
                self.active = true
                self.onPress?()
            }
            pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
        } else {
            pending?.cancel()
            pending = nil
            if active {
                active = false
                onRelease?()
            }
        }
    }

    private func otherKey() {
        pending?.cancel()
        pending = nil
        if active {
            active = false
            onCancel?()
        }
    }
}
