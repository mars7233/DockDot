import AppKit
import QuartzCore

@available(macOS 26.0, *)
final class LauncherPanel: NSPanel {
    var onCancel: (() -> Void)?
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // 液态玻璃自带光影，不用窗口阴影
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }
    override var canBecomeKey: Bool { true }

    // 让玻璃始终按「激活」状态渲染（和系统 Dock 一样清透）；面板本身不会抢走其他 App 的激活状态
    @objc(_hasActiveAppearance) func dd_hasActiveAppearance() -> Bool { true }
    @objc(_hasActiveAppearanceIgnoringKeyFocus) func dd_hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc(_hasKeyAppearance) func dd_hasKeyAppearance() -> Bool { true }
    @objc(_hasMainAppearance) func dd_hasMainAppearance() -> Bool { true }
    @objc(_hasActiveControls) func dd_hasActiveControls() -> Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }   // Esc
}

@available(macOS 26.0, *)
enum Anchor {
    case mouse
    case dot(NSRect, Edge)
}

@available(macOS 26.0, *)
final class LauncherController {
    private let panel = LauncherPanel()
    private let root = NSView()
    private let radial = RadialView()
    private var outsideClickMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init() {
        panel.contentView = root
        root.addSubview(radial)
        panel.onCancel = { [weak self] in self?.close() }
        radial.onLaunch = { [weak self] in self?.launch($0) }
        radial.onClose = { [weak self] in self?.close() }
    }

    func show(anchor: Anchor) {
        let (pinned, running) = DockReader.items()
        let size = radial.configure(pinned: pinned, running: running)
        panel.setContentSize(size)
        position(anchor, size: size)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        radial.refreshGlass()
        panel.makeFirstResponder(radial)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        if outsideClickMonitor == nil {
            // 点其他 App 的地方就收起
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.close()
            }
        }
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
    }

    private func launch(_ item: DockItem) {
        close()
        DockReader.open(item)
    }

    private func position(_ anchor: Anchor, size s: NSSize) {
        var o: NSPoint
        let ref: NSPoint
        switch anchor {
        case .mouse:
            // 圆心对准鼠标，鼠标往哪个方向移就选哪个
            ref = NSEvent.mouseLocation
            o = NSPoint(x: ref.x - s.width / 2, y: ref.y - s.height / 2)
        case let .dot(r, edge):
            ref = NSPoint(x: r.midX, y: r.midY)
            let g: CGFloat = 12
            switch edge {
            case .left: o = NSPoint(x: r.maxX + g, y: r.midY - s.height / 2)
            case .right: o = NSPoint(x: r.minX - g - s.width, y: r.midY - s.height / 2)
            case .bottom: o = NSPoint(x: r.midX - s.width / 2, y: r.maxY + g)
            case .top: o = NSPoint(x: r.midX - s.width / 2, y: r.minY - g - s.height)
            }
        }
        let vf = (NSScreen.screens.first { $0.frame.contains(ref) } ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        o.x = min(max(o.x, vf.minX + 6), vf.maxX - s.width - 6)
        o.y = min(max(o.y, vf.minY + 6), vf.maxY - s.height - 6)
        panel.setFrameOrigin(o)
    }
}
