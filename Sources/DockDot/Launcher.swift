import AppKit
import QuartzCore

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
    override func cancelOperation(_ sender: Any?) { onCancel?() }   // Esc
}

/// 只负责画在玻璃上面的东西：圆心边上指向选中图标的小弧
private final class OverlayView: NSView {
    var drawer: ((NSRect) -> Void)?
    override func draw(_ dirtyRect: NSRect) { drawer?(dirtyRect) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 液态玻璃环形菜单。
/// 每个图标是一颗玻璃泡，挨得够近的玻璃泡会被 NSGlassEffectContainerView 融成一整圈；
/// 圆心也是一块玻璃，显示当前指向的 App。鼠标指向哪个方向就选中哪个图标，点击打开。
final class RadialView: NSView {
    private struct Slot {
        let item: DockItem
        let center: NSPoint
        let ring: Int
        let angle: CGFloat
        let bubble: NSGlassEffectView
    }

    var onLaunch: ((DockItem) -> Void)?
    var onClose: (() -> Void)?

    private let bubble: CGFloat = 62        // 玻璃泡直径
    private let bigBubble: CGFloat = 78     // 选中时的直径
    private let iconInset: CGFloat = 7
    private let step: CGFloat = 68          // 相邻玻璃泡的弧长（< 直径 + spacing 才会融在一起）
    private let maxSingleRing = 22

    private var slots: [Slot] = []
    private var radii: [CGFloat] = []
    private var R: CGFloat = 0              // 整体半径
    private var hubR: CGFloat = 0
    private let glass = NSGlassEffectContainerView()
    private let glassContent = NSView()
    private let hub = NSGlassEffectView()
    private let overlay = OverlayView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")

    private var selected: Int? {
        didSet {
            guard selected != oldValue else { return }
            if let o = oldValue { setBubble(o, big: false) }
            if let s = selected { setBubble(s, big: true) }
            updateHub()
            overlay.needsDisplay = true
        }
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    /// 重新布局，返回需要的窗口大小
    func configure(pinned: [DockItem], running: [DockItem]) -> NSSize {
        subviews.forEach { $0.removeFromSuperview() }
        glassContent.subviews.forEach { $0.removeFromSuperview() }
        slots = []
        selected = nil

        // nil = 固定 App 和「未固定但在运行」的 App 之间留的空位，相当于 Dock 上的分隔线
        var entries: [DockItem?] = pinned
        if !pinned.isEmpty && !running.isEmpty { entries.append(nil) }
        entries += running

        var rings: [[DockItem?]]
        if entries.count <= maxSingleRing {
            rings = [entries]
        } else {
            let innerCap = Int(floor(2 * .pi * 165 / step))
            rings = [Array(entries[..<innerCap]), Array(entries[innerCap...])]
        }
        radii = []
        for (k, ring) in rings.enumerated() {
            var r = max(k == 0 ? 116 : 0, CGFloat(ring.count) * step / (2 * .pi))
            if k > 0 { r = max(r, radii[k - 1] + step + 8) }
            radii.append(r)
        }
        if entries.isEmpty { radii = [116] }
        R = (radii.last ?? 116) + bigBubble / 2 + 10
        hubR = min(72, radii[0] - bubble / 2 - 26)
        let size = NSSize(width: R * 2, height: R * 2)
        frame = NSRect(origin: .zero, size: size)
        let c = NSPoint(x: R, y: R)

        // 玻璃层
        glass.frame = bounds
        glass.spacing = 18
        glassContent.frame = bounds
        glass.contentView = glassContent
        addSubview(glass)

        hub.frame = circle(c, hubR)
        hub.cornerRadius = hubR
        hub.style = .regular
        glassContent.addSubview(hub)
        let hubContent = NSView(frame: hub.bounds)
        hub.contentView = hubContent
        for l in [nameLabel, subLabel] {
            l.alignment = .center
            l.lineBreakMode = .byTruncatingTail
            l.removeFromSuperview()
            hubContent.addSubview(l)
        }
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .labelColor
        subLabel.font = .systemFont(ofSize: 11)
        subLabel.textColor = .secondaryLabelColor
        let w = hubR * 2 - 16
        nameLabel.frame = NSRect(x: hubR - w / 2, y: hubR - 2, width: w, height: 18)
        subLabel.frame = NSRect(x: hubR - w / 2, y: hubR - 19, width: w, height: 15)

        var order = 0
        for (k, ring) in rings.enumerated() {
            for (i, entry) in ring.enumerated() {
                guard let item = entry else { continue }
                let a = CGFloat.pi / 2 - 2 * .pi * CGFloat(i) / CGFloat(ring.count)   // 从正上方顺时针
                let p = NSPoint(x: c.x + radii[k] * cos(a), y: c.y + radii[k] * sin(a))
                let b = makeBubble(item, at: p)
                glassContent.addSubview(b)
                popIn(b, delay: Double(order) * 0.012)
                order += 1
                slots.append(Slot(item: item, center: p, ring: k, angle: a, bubble: b))
            }
        }

        overlay.frame = bounds
        overlay.drawer = { [weak self] _ in self?.drawOverlay() }
        addSubview(overlay)

        updateHub()
        needsDisplay = true
        return size
    }

    private func makeBubble(_ item: DockItem, at p: NSPoint) -> NSGlassEffectView {
        let b = NSGlassEffectView(frame: circle(p, bubble / 2))
        b.cornerRadius = bigBubble / 2          // 取大值，大小变化时始终是正圆
        b.style = .regular
        b.wantsLayer = true
        let content = NSView(frame: b.bounds)
        content.autoresizingMask = [.width, .height]

        let iv = NSImageView(frame: b.bounds.insetBy(dx: iconInset, dy: iconInset))
        iv.image = item.icon
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.autoresizingMask = [.width, .height]
        content.addSubview(iv)

        if item.isRunning {
            let d = NSView(frame: NSRect(x: bubble / 2 - 2, y: 2, width: 4, height: 4))
            d.wantsLayer = true
            d.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.75).cgColor
            d.layer?.cornerRadius = 2
            d.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
            content.addSubview(d)
        }
        b.contentView = content
        return b
    }

    private func circle(_ c: NSPoint, _ r: CGFloat) -> NSRect {
        NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    private func setBubble(_ i: Int, big: Bool) {
        guard slots.indices.contains(i) else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            slots[i].bubble.animator().frame = circle(slots[i].center, (big ? bigBubble : bubble) / 2)
        }
    }

    private func popIn(_ v: NSView, delay: Double) {
        guard let layer = v.layer else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0
        a.toValue = 1
        a.duration = 0.2
        a.beginTime = CACurrentMediaTime() + delay
        a.fillMode = .backwards
        layer.add(a, forKey: "pop")
    }

    private func updateHub() {
        if let s = selected {
            let it = slots[s].item
            nameLabel.stringValue = it.name
            subLabel.stringValue = it.isRunning ? (it.isPinned ? "运行中" : "运行中 · 未固定") : "未运行"
        } else {
            nameLabel.stringValue = slots.isEmpty ? "Dock 上没有 App" : "\(slots.count) 个 App"
            subLabel.stringValue = "指向图标，点击打开"
        }
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 几乎透明的底：让玻璃之间的空隙也能接到鼠标（全透明像素会点穿到后面的窗口）
        NSColor.black.withAlphaComponent(0.004).setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    private func drawOverlay() {
        guard let s = selected else { return }
        let c = NSPoint(x: R, y: R)
        let deg = slots[s].angle * 180 / .pi
        let arc = NSBezierPath()
        arc.appendArc(withCenter: c, radius: hubR - 4, startAngle: deg - 16, endAngle: deg + 16)
        arc.lineWidth = 3
        arc.lineCapStyle = .round
        NSColor.controlAccentColor.setStroke()
        arc.stroke()
    }

    // MARK: 鼠标

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }

    private func slot(at p: NSPoint) -> Int? {
        let dx = p.x - R, dy = p.y - R
        let d = hypot(dx, dy)
        guard d > hubR, d <= R, !slots.isEmpty else { return nil }
        let ring = radii.indices.min(by: { abs(radii[$0] - d) < abs(radii[$1] - d) }) ?? 0
        let a = atan2(dy, dx)
        func diff(_ x: CGFloat) -> CGFloat {
            var t = abs(x - a).truncatingRemainder(dividingBy: 2 * .pi)
            if t > .pi { t = 2 * .pi - t }
            return t
        }
        let candidates = slots.indices.filter { slots[$0].ring == ring }
        guard let best = candidates.min(by: { diff(slots[$0].angle) < diff(slots[$1].angle) }) else { return nil }
        // 指向分隔空位时不选
        let perSlot = step / radii[ring]
        return diff(slots[best].angle) <= perSlot * 0.6 ? best : nil
    }

    override func mouseMoved(with event: NSEvent) { selected = slot(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { selected = nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let s = slot(at: p) {
            onLaunch?(slots[s].item)
        } else if hypot(p.x - R, p.y - R) <= hubR {
            onClose?()
        }
    }

    // MARK: 键盘：←→ 切换，回车打开，Esc 关闭

    override func keyDown(with event: NSEvent) {
        guard !slots.isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123, 126: selected = ((selected ?? 0) - 1 + slots.count) % slots.count
        case 124, 125: selected = selected.map { ($0 + 1) % slots.count } ?? 0
        case 36, 76: if let s = selected { onLaunch?(slots[s].item) }
        case 53: onClose?()
        default: super.keyDown(with: event)
        }
    }
}

enum Anchor {
    case mouse
    case dot(NSRect, Edge)
}

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
