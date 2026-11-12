import AppKit
import QuartzCore

/// 选中时在图标后面的柔和光圈（颜色在 draw 里取，随玻璃的深浅自动适配）
private final class HighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        p.fill()
        NSColor.labelColor.withAlphaComponent(0.14).setStroke()
        p.lineWidth = 1
        p.stroke()
    }
}

/// 运行中的小点
private final class DotMark: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// 一整块液态玻璃圆盘：图标沿边缘排一圈，中间显示当前指向的 App。
/// 鼠标从圆心往哪个方向移就选中那个方向的图标（不必精确放在图标上），点击打开；
/// 选中的光圈会在图标之间滑动。
final class RadialView: NSView {
    private struct Slot {
        let item: DockItem
        let center: NSPoint
        let ring: Int
        let angle: CGFloat
        let icon: NSImageView
    }

    var onLaunch: ((DockItem) -> Void)?
    var onClose: (() -> Void)?

    private let iconSize: CGFloat = 48
    private let step: CGFloat = 64          // 相邻图标的弧长
    private let maxSingleRing = 22
    private let deadZone: CGFloat = 34      // 圆心附近不选任何图标

    private var slots: [Slot] = []
    private var radii: [CGFloat] = []
    private var R: CGFloat = 0
    private let disc = NSGlassEffectView()
    private let content = NSView()
    private let highlight = HighlightView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")

    private var selected: Int? {
        didSet {
            guard selected != oldValue else { return }
            if let o = oldValue { setIcon(o, big: false) }
            if let s = selected { setIcon(s, big: true) }
            moveHighlight(from: oldValue)
            updateCenter()
        }
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    /// 重新布局，返回需要的窗口大小
    func configure(pinned: [DockItem], running: [DockItem]) -> NSSize {
        content.subviews.forEach { $0.removeFromSuperview() }
        slots = []
        selected = nil

        // nil = 固定 App 和「未固定但在运行」的 App 之间空一格，相当于 Dock 上的分隔线
        var entries: [DockItem?] = pinned
        if !pinned.isEmpty && !running.isEmpty { entries.append(nil) }
        entries += running

        var rings: [[DockItem?]]
        if entries.count <= maxSingleRing {
            rings = [entries]
        } else {
            let innerCap = Int(floor(2 * .pi * 160 / step))
            rings = [Array(entries[..<innerCap]), Array(entries[innerCap...])]
        }
        radii = []
        for (k, ring) in rings.enumerated() {
            var r = max(k == 0 ? 118 : 0, CGFloat(ring.count) * step / (2 * .pi))
            if k > 0 { r = max(r, radii[k - 1] + step + 4) }
            radii.append(r)
        }
        if entries.isEmpty { radii = [118] }
        R = (radii.last ?? 118) + iconSize / 2 + 24
        let size = NSSize(width: R * 2, height: R * 2)
        frame = NSRect(origin: .zero, size: size)
        let c = NSPoint(x: R, y: R)

        disc.frame = bounds
        disc.cornerRadius = R
        disc.style = .regular
        // 轻微着色，压住背后杂乱的文字/窗口，保持图标清楚
        disc.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.45)
        content.frame = disc.bounds
        disc.contentView = content
        if disc.superview == nil { addSubview(disc) }

        highlight.alphaValue = 0
        content.addSubview(highlight)

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
                content.addSubview(iv)
                if item.isRunning {
                    // 小点放在图标朝圆心的一侧
                    let d = iconSize / 2 + 6
                    let m = DotMark(frame: circle(NSPoint(x: p.x - d * cos(a), y: p.y - d * sin(a)), 2))
                    content.addSubview(m)
                }
                popIn(iv, delay: Double(order) * 0.012)
                order += 1
                slots.append(Slot(item: item, center: p, ring: k, angle: a, icon: iv))
            }
        }

        let w = max(120, (radii[0] - iconSize / 2 - 22) * 2)
        for l in [nameLabel, subLabel] {
            l.alignment = .center
            l.lineBreakMode = .byTruncatingTail
            content.addSubview(l)
        }
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .labelColor
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = .secondaryLabelColor
        nameLabel.frame = NSRect(x: c.x - w / 2, y: c.y - 1, width: w, height: 21)
        subLabel.frame = NSRect(x: c.x - w / 2, y: c.y - 21, width: w, height: 16)
        updateCenter()
        return size
    }

    private func circle(_ c: NSPoint, _ r: CGFloat) -> NSRect {
        NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    private func iconRect(_ p: NSPoint, big: Bool) -> NSRect {
        circle(p, (big ? iconSize * 1.14 : iconSize) / 2)
    }

    private func setIcon(_ i: Int, big: Bool) {
        guard slots.indices.contains(i) else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            slots[i].icon.animator().frame = iconRect(slots[i].center, big: big)
        }
    }

    /// 光圈：第一次出现时淡入，之后在图标之间滑动
    private func moveHighlight(from old: Int?) {
        guard let s = selected else {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; highlight.animator().alphaValue = 0 }
            return
        }
        let target = circle(slots[s].center, iconSize / 2 + 11)
        if old == nil || highlight.alphaValue == 0 {
            highlight.frame = target
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; highlight.animator().alphaValue = 1 }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                highlight.animator().frame = target
            }
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

    private func updateCenter() {
        if let s = selected {
            let it = slots[s].item
            nameLabel.stringValue = it.name
            subLabel.stringValue = it.isRunning ? (it.isPinned ? "运行中" : "运行中 · 未固定") : "未运行"
        } else {
            nameLabel.stringValue = slots.isEmpty ? "Dock 上没有 App" : "\(slots.count) 个 App"
            subLabel.stringValue = "指向图标，点击打开"
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
        guard d > deadZone, d <= R, !slots.isEmpty else { return nil }
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
        } else if hypot(p.x - R, p.y - R) <= deadZone {
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
