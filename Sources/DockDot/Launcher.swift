import AppKit
import QuartzCore

final class LauncherPanel: NSPanel {
    var onCancel: (() -> Void)?
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }   // Esc
}

/// 圆形环绕菜单：中间是圆心（显示当前指向的 App），图标绕成一圈。
/// 鼠标指向哪个方向就选中那个方向的图标（不必精确放在图标上），点击打开。
final class RadialView: NSView {
    private struct Slot {
        let item: DockItem
        let center: NSPoint
        let ring: Int
        let angle: CGFloat
        let view: NSImageView
    }

    var onLaunch: ((DockItem) -> Void)?
    var onClose: (() -> Void)?

    private let iconSize: CGFloat = 50
    private let step: CGFloat = 68          // 相邻图标的弧长
    private let maxSingleRing = 22
    private let margin: CGFloat = 18
    private var bandInner: CGFloat = 0      // 图标圆环的内边缘

    private var slots: [Slot] = []
    private var radii: [CGFloat] = []
    private var R: CGFloat = 0              // 外圆半径
    private var hubR: CGFloat = 0
    private let nameLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")

    private var selected: Int? {
        didSet {
            guard selected != oldValue else { return }
            if let o = oldValue { setIcon(o, big: false) }
            if let s = selected { setIcon(s, big: true) }
            updateHub()
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    /// 重新布局，返回需要的窗口大小
    func configure(pinned: [DockItem], running: [DockItem]) -> NSSize {
        subviews.forEach { $0.removeFromSuperview() }
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
            var r = max(k == 0 ? 112 : 0, CGFloat(ring.count) * step / (2 * .pi))
            if k > 0 { r = max(r, radii[k - 1] + step + 6) }
            radii.append(r)
        }
        if entries.isEmpty { radii = [112] }
        R = (radii.last ?? 112) + iconSize / 2 + margin
        bandInner = radii[0] - iconSize / 2 - margin
        hubR = min(70, bandInner - 24)
        let size = NSSize(width: R * 2, height: R * 2)
        frame = NSRect(origin: .zero, size: size)

        let c = NSPoint(x: R, y: R)
        var order = 0
        for (k, ring) in rings.enumerated() {
            for (i, entry) in ring.enumerated() {
                guard let item = entry else { continue }
                let a = CGFloat.pi / 2 - 2 * .pi * CGFloat(i) / CGFloat(ring.count)   // 从正上方顺时针
                let p = NSPoint(x: c.x + radii[k] * cos(a), y: c.y + radii[k] * sin(a))
                let iv = NSImageView(frame: iconRect(p, big: false))
                iv.image = item.icon
                iv.imageScaling = .scaleProportionallyUpOrDown
                iv.wantsLayer = true
                addSubview(iv)
                popIn(iv, delay: Double(order) * 0.012)
                order += 1
                slots.append(Slot(item: item, center: p, ring: k, angle: a, view: iv))
            }
        }

        for l in [nameLabel, subLabel] {
            l.alignment = .center
            l.lineBreakMode = .byTruncatingTail
            l.textColor = .white
            addSubview(l)
        }
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subLabel.font = .systemFont(ofSize: 11)
        subLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        let w = hubR * 2 - 14
        nameLabel.frame = NSRect(x: c.x - w / 2, y: c.y - 2, width: w, height: 20)
        subLabel.frame = NSRect(x: c.x - w / 2, y: c.y - 20, width: w, height: 15)
        updateHub()
        needsDisplay = true
        return size
    }

    private func iconRect(_ p: NSPoint, big: Bool) -> NSRect {
        let s = big ? iconSize * 1.22 : iconSize
        return NSRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
    }

    private func setIcon(_ i: Int, big: Bool) {
        guard slots.indices.contains(i) else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            slots[i].view.animator().frame = iconRect(slots[i].center, big: big)
        }
    }

    private func popIn(_ v: NSView, delay: Double) {
        guard let layer = v.layer else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 0
        a.toValue = 1
        a.duration = 0.18
        a.beginTime = CACurrentMediaTime() + delay
        a.fillMode = .backwards
        layer.add(a, forKey: "pop")
    }

    private func updateHub() {
        if let s = selected {
            let it = slots[s].item
            nameLabel.stringValue = it.name
            subLabel.stringValue = it.isRunning ? (it.isPinned ? "运行中" : "运行中 · 未固定在 Dock") : "未运行"
        } else {
            nameLabel.stringValue = slots.isEmpty ? "Dock 上没有 App" : "\(slots.count) 个 App"
            subLabel.stringValue = "指向图标，点击打开"
        }
    }

    // MARK: 绘制

    private func circle(_ c: NSPoint, _ r: CGFloat) -> NSRect {
        NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    /// 窗口形状：外面一圈放图标的圆环 + 中间的小圆心，两者之间透明
    func shapeMask() -> NSImage {
        let c = NSPoint(x: R, y: R)
        return NSImage(size: bounds.size, flipped: false) { [self] _ in
            NSColor.black.setFill()
            let band = NSBezierPath(ovalIn: circle(c, R))
            band.append(NSBezierPath(ovalIn: circle(c, bandInner)).reversed)
            band.fill()
            NSBezierPath(ovalIn: circle(c, hubR)).fill()
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSPoint(x: R, y: R)

        // 透明空隙里也要能接到鼠标（全透明像素会点穿到后面的窗口）
        NSColor.black.withAlphaComponent(0.004).setFill()
        NSBezierPath(ovalIn: circle(c, bandInner)).fill()

        // 圆环：压暗毛玻璃 + 内外细描边
        let band = NSBezierPath(ovalIn: circle(c, R))
        band.append(NSBezierPath(ovalIn: circle(c, bandInner)).reversed)
        NSColor.black.withAlphaComponent(0.42).setFill()
        band.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        for r in [R - 0.5, bandInner + 0.5] {
            let p = NSBezierPath(ovalIn: circle(c, r))
            p.lineWidth = 1
            p.stroke()
        }

        // 选中扇区的高亮
        if let s = selected {
            let sl = slots[s]
            let hr = iconSize * 0.62 + 6
            NSColor.white.withAlphaComponent(0.2).setFill()
            NSBezierPath(ovalIn: NSRect(x: sl.center.x - hr, y: sl.center.y - hr, width: hr * 2, height: hr * 2)).fill()
        }

        // 运行中的小点：画在图标朝圆心一侧
        for sl in slots where sl.item.isRunning {
            let d: CGFloat = iconSize / 2 + 7
            let p = NSPoint(x: sl.center.x - d * cos(sl.angle), y: sl.center.y - d * sin(sl.angle))
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)).fill()
        }

        // 圆心
        let hub = NSBezierPath(ovalIn: circle(c, hubR))
        NSColor.black.withAlphaComponent(0.4).setFill()
        hub.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        hub.lineWidth = 1
        hub.stroke()

        // 圆心边缘指向选中图标的小弧
        if let s = selected {
            let deg = slots[s].angle * 180 / .pi
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: hubR - 1, startAngle: deg - 14, endAngle: deg + 14)
            arc.lineWidth = 3
            arc.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.9).setStroke()
            arc.stroke()
        }
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
    private let effect = NSVisualEffectView()
    private let radial = RadialView()
    private var outsideClickMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init() {
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = effect
        effect.addSubview(radial)
        panel.onCancel = { [weak self] in self?.close() }
        radial.onLaunch = { [weak self] in self?.launch($0) }
        radial.onClose = { [weak self] in self?.close() }
    }

    func show(anchor: Anchor) {
        let (pinned, running) = DockReader.items()
        let size = radial.configure(pinned: pinned, running: running)
        panel.setContentSize(size)
        effect.maskImage = radial.shapeMask()
        position(anchor, size: size)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(radial)
        panel.invalidateShadow()
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
