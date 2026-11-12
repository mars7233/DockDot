import AppKit

@available(macOS 26.0, *)
enum Edge { case left, right, top, bottom }

@available(macOS 26.0, *)
final class DotPanel: NSPanel {
    init(size: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 仿 iPhone 小圆点：圆角方块 + 三层同心圆
@available(macOS 26.0, *)
final class DotView: NSView {
    var onClick: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var idleAlpha: CGFloat = 0.45

    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragging = false

    override func draw(_ dirtyRect: NSRect) {
        let s = bounds.width
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: s * 0.28, yRadius: s * 0.28)
        NSColor.black.withAlphaComponent(0.6).setFill()
        bg.fill()
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        for (r, a) in [(0.36, 0.22), (0.28, 0.38), (0.2, 0.95)] as [(CGFloat, CGFloat)] {
            let rr = s * r
            NSColor.white.withAlphaComponent(a).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)).fill()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { fade(to: 1) }
    override func mouseExited(with event: NSEvent) { if !dragging { fade(to: idleAlpha) } }

    func fade(to a: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window?.animator().alphaValue = a
        }
    }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - startMouse.x, dy = p.y - startMouse.y
        if !dragging, hypot(dx, dy) > 3 {
            dragging = true
            onDragStart?()
        }
        if dragging { window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            dragging = false
            onDragEnd?()
            if !(window?.frame.contains(NSEvent.mouseLocation) ?? false) { fade(to: idleAlpha) }
        } else {
            onClick?()
        }
    }
}

@available(macOS 26.0, *)
final class DotController {
    let size: CGFloat = 50
    let window: DotPanel
    private let view: DotView
    private(set) var edge: Edge = .right
    var onClick: (() -> Void)?
    var onDragStart: (() -> Void)?

    private let defaultsKey = "dotCenter"

    init() {
        window = DotPanel(size: size)
        view = DotView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        window.contentView = view
        view.idleAlpha = CGFloat(AppSettings.shared.dotIdleAlpha)
        window.alphaValue = view.idleAlpha
        view.onClick = { [weak self] in self?.onClick?() }
        view.onDragStart = { [weak self] in self?.onDragStart?() }
        view.onDragEnd = { [weak self] in self?.snap(animated: true) }
        restorePosition()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.snap(animated: false)
        }
    }

    var isVisible: Bool { window.isVisible }

    /// 设置变化时调用：空闲透明度、显示/隐藏
    func applySettings() {
        let s = AppSettings.shared
        view.idleAlpha = CGFloat(s.dotIdleAlpha)
        if !window.frame.contains(NSEvent.mouseLocation) { window.alphaValue = view.idleAlpha }
        if s.dotVisible && !isVisible { show() } else if !s.dotVisible && isVisible { hide() }
    }
    func show() { window.orderFrontRegardless() }
    func hide() { window.orderOut(nil) }

    private func restorePosition() {
        if let s = UserDefaults.standard.string(forKey: defaultsKey) {
            let c = NSPointFromString(s)
            if NSScreen.screens.contains(where: { $0.frame.contains(c) }) {
                window.setFrameOrigin(NSPoint(x: c.x - size / 2, y: c.y - size / 2))
                snap(animated: false)
                return
            }
        }
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        window.setFrameOrigin(NSPoint(x: vf.maxX - size, y: vf.midY))
        snap(animated: false)
    }

    /// 松手后吸附到最近的屏幕边缘
    func snap(animated: Bool) {
        let f = window.frame
        let c = NSPoint(x: f.midX, y: f.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(c) })
                ?? NSScreen.screens.min(by: { dist($0.frame, c) < dist($1.frame, c) }) else { return }
        let vf = screen.visibleFrame
        let m: CGFloat = 4
        let cx = min(max(f.minX, vf.minX + m), vf.maxX - size - m)
        let cy = min(max(f.minY, vf.minY + m), vf.maxY - size - m)
        let d: [(Edge, CGFloat)] = [(.left, c.x - vf.minX), (.right, vf.maxX - c.x),
                                    (.bottom, c.y - vf.minY), (.top, vf.maxY - c.y)]
        edge = d.min(by: { $0.1 < $1.1 })!.0
        var o = NSPoint(x: cx, y: cy)
        switch edge {
        case .left: o.x = vf.minX + m
        case .right: o.x = vf.maxX - size - m
        case .bottom: o.y = vf.minY + m
        case .top: o.y = vf.maxY - size - m
        }
        let target = NSRect(origin: o, size: f.size)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(target, display: true)
            }
        } else {
            window.setFrame(target, display: true)
        }
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: target.midX, y: target.midY)), forKey: defaultsKey)
    }

    private func dist(_ r: NSRect, _ p: NSPoint) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}
