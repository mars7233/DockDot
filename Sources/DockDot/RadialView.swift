import AppKit
import QuartzCore

// 颜色都在 draw 里取系统动态色：玻璃会按背后的明暗自动切换深/浅外观，
// 文字和小点跟着变（浅背景深字、深背景浅字），不用自己加阴影或暗底。

/// 选中时图标后面的柔光：中间淡、边缘渐隐，没有描边
@available(macOS 26.0, *)
private final class HighlightView: NSView {
    var strength: CGFloat = 0.10 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let g = NSGradient(colors: [NSColor.labelColor.withAlphaComponent(strength),
                                    NSColor.labelColor.withAlphaComponent(strength * 0.6),
                                    NSColor.labelColor.withAlphaComponent(0)])
        g?.draw(in: NSBezierPath(ovalIn: bounds), relativeCenterPosition: .zero)
    }
}

/// 运行中的小点
@available(macOS 26.0, *)
private final class DotMark: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.8).setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// 面板里的图标布局，两种排列：
/// - 一圈：图标沿圆排一圈（玻璃可以是整块圆盘或只有图标那一圈的圆环），中间显示当前指向的 App；
///   鼠标从圆心往哪个方向移就选中那个方向的图标。
/// - 蜂窝：像 Apple Watch 的应用页，图标排成六边形网格，第一个在正中、其余由内向外一圈圈排，
///   越往外越小；鼠标停在哪个图标上就选中哪个，名称显示在图标上方的小玻璃标签里。
@available(macOS 26.0, *)
final class RadialView: NSView {
    enum Layout { case ring, grid }

    private struct Slot {
        let item: DockItem
        let center: NSPoint     // 在玻璃内容坐标里
        let ring: Int           // 一圈：0；蜂窝：第几圈（0 是正中）
        let angle: CGFloat      // 一圈：方向角
        let scale: CGFloat      // 蜂窝：越往外越小
        let icon: NSImageView
    }

    var onLaunch: ((DockItem) -> Void)?
    var onClose: (() -> Void)?

    /// 设置窗口里的预览：不播放出场动画，点击不打开 App
    var isPreview = false

    private var iconSize: CGFloat = 48      // 由设置决定
    private var step: CGFloat { iconSize + 16 }   // 一圈：相邻图标的弧长
    private var cell: CGFloat { iconSize + 14 }   // 蜂窝：相邻图标的中心距
    private let deadZone: CGFloat = 34      // 一圈：圆心附近不选任何图标
    private let gridPad: CGFloat = 36       // 蜂窝：玻璃外面留给名称标签的空间

    private(set) var layout: Layout = .ring
    private var slots: [Slot] = []
    private var ringRadius: CGFloat = 0
    private var R: CGFloat = 0              // 玻璃半径
    private var origin: NSPoint = .zero     // 玻璃在视图里的左下角
    private let disc = NSGlassEffectView()
    private let hub = NSGlassEffectView()      // 一圈：圆心那块小玻璃
    private let hubContent = NSView()
    private let content = NSView()
    private let highlight = HighlightView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")
    private let nameTag = NSGlassEffectView()      // 蜂窝：名称标签
    private let tagLabel = NSTextField(labelWithString: "")

    private var selected: Int? {
        didSet {
            guard selected != oldValue else { return }
            if let o = oldValue { setIcon(o, big: false) }
            if let s = selected { setIcon(s, big: true) }
            moveHighlight(from: oldValue)
            updateLabels()
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
        let s = AppSettings.shared
        iconSize = CGFloat(s.iconSize)
        highlight.strength = CGFloat(s.highlightStrength)
        let m = CGFloat(s.edgeMargin)

        // 固定的 App 在前，未固定但在运行的接在后面
        let items = pinned + running
        layout = s.resolvedLayout(appCount: items.count) == .grid ? .grid : .ring

        // ---- 位置 ----
        var places: [(p: NSPoint, ring: Int, angle: CGFloat, scale: CGFloat)] = []
        if layout == .ring {
            ringRadius = max(118, CGFloat(items.count) * step / (2 * .pi))
            R = ringRadius + iconSize / 2 + m      // 图标离玻璃边缘留足距离，边缘的高光不会压在图标底下
            for i in items.indices {
                let a = CGFloat.pi / 2 - 2 * .pi * CGFloat(i) / CGFloat(max(items.count, 1))   // 从正上方顺时针
                places.append((NSPoint(x: ringRadius * cos(a), y: ringRadius * sin(a)), 0, a, 1))
            }
        } else {
            let hex = Self.hexSpiral(count: items.count)
            var maxEdge: CGFloat = iconSize / 2
            for h in hex {
                let scale = max(0.72, 1 - 0.08 * CGFloat(h.ring))       // 越往外越小
                let p = NSPoint(x: cell * (CGFloat(h.q) + CGFloat(h.r) / 2), y: cell * CGFloat(h.r) * sqrt(3) / 2)
                places.append((p, h.ring, atan2(p.y, p.x), scale))
                maxEdge = max(maxEdge, hypot(p.x, p.y) + iconSize * scale / 2)
            }
            R = maxEdge + m
        }
        let pad = layout == .grid ? gridPad : 0
        origin = NSPoint(x: pad, y: pad)
        let size = NSSize(width: (R + pad) * 2, height: (R + pad) * 2)
        frame = NSRect(origin: .zero, size: size)
        let c = NSPoint(x: R, y: R)        // 玻璃内容坐标里的圆心

        // ---- 玻璃 ----
        disc.frame = NSRect(x: origin.x, y: origin.y, width: R * 2, height: R * 2)
        disc.cornerRadius = R
        // 「程序坞」样式：和系统 Dock 同一种私有材质（见 DockGlass）；不支持时退回透明玻璃
        disc.style = s.glassStyle == .regular ? .regular : .clear
        if s.glassStyle == .dock { DockGlass.applyDockMaterial(disc) }
        disc.tintColor = s.effectiveTint
        // 一圈 + 圆环：只在图标那一圈放玻璃，中间留空；蜂窝和圆盘都是整块
        if layout == .ring && s.discShape == .ring {
            DockGlass.setShape(disc, DockGlass.ringPath(center: c, outer: R, inner: max(20, ringRadius - iconSize / 2 - m)))
        } else {
            DockGlass.setShape(disc, nil)
        }
        disc.clipsToBounds = false
        if #available(macOS 27.0, *) {
            disc.effectIsInteractive = s.effectiveInteractive // 鼠标悬停/按下时玻璃本身会有反应
        }
        content.frame = disc.bounds
        disc.contentView = content
        if disc.superview == nil { addSubview(disc) }

        highlight.alphaValue = 0
        content.addSubview(highlight)

        // ---- 图标 ----
        for (i, item) in items.enumerated() {
            let pl = places[i]
            let p = NSPoint(x: c.x + pl.p.x, y: c.y + pl.p.y)
            let iv = NSImageView(frame: iconRect(p, scale: pl.scale, big: false))
            iv.image = item.icon
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            content.addSubview(iv)
            if item.isRunning && s.showRunningDots {
                let mark: NSPoint
                if layout == .ring {
                    let d = iconSize / 2 + 6          // 一圈：小点在图标朝圆心的一侧
                    mark = NSPoint(x: p.x - d * cos(pl.angle), y: p.y - d * sin(pl.angle))
                } else {
                    mark = NSPoint(x: p.x, y: p.y - iconSize * pl.scale / 2 - 4)   // 蜂窝：图标正下方
                }
                content.addSubview(DotMark(frame: circle(mark, 2)))
            }
            if !isPreview { popIn(iv, delay: Double(i) * 0.012) }
            slots.append(Slot(item: item, center: p, ring: pl.ring, angle: pl.angle, scale: pl.scale, icon: iv))
        }

        configureLabels(c: c, settings: s)
        updateLabels()
        if s.glassStyle == .dock { DockGlass.finish(glasses) }
        return size
    }

    /// 六边形网格的螺旋顺序：先正中，再一圈圈往外（每圈从左上开始顺时针）
    private static func hexSpiral(count: Int) -> [(q: Int, r: Int, ring: Int)] {
        var out: [(Int, Int, Int)] = [(0, 0, 0)]
        let dirs = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]
        var k = 1
        while out.count < count {
            var q = -k, r = k                     // 这一圈的起点：左上
            for d in dirs {
                for _ in 0..<k where out.count < count {
                    out.append((q, r, k))
                    q += d.0; r += d.1
                }
            }
            k += 1
        }
        return Array(out.prefix(count)).map { (q: $0.0, r: $0.1, ring: $0.2) }
    }

    private var glasses: [NSGlassEffectView] {
        var g = [disc]
        if !hub.isHidden { g.append(hub) }
        return g
    }

    private func configureLabels(c: NSPoint, settings s: AppSettings) {
        if layout == .ring {
            nameTag.isHidden = true
            // 圆心：一小块玻璃，文字放在它里面；系统会按背景明暗自动选深色/浅色字。
            // 关掉「圆心玻璃」时文字直接放在外圈玻璃上
            let ringInner = ringRadius - iconSize / 2 - CGFloat(s.edgeMargin)
            let lensR = s.discShape == .ring ? min(80, ringInner - 16) : min(80, ringRadius - iconSize / 2 - 14)
            let w = lensR * 2 - 18
            let host: NSView
            let hc: NSPoint
            if s.showCenterLens {
                hub.frame = circle(NSPoint(x: origin.x + c.x, y: origin.y + c.y), lensR)
                hub.cornerRadius = lensR
                hub.style = .regular
                if s.glassStyle == .dock { DockGlass.applyDockMaterial(hub) }
                hub.tintColor = nil
                hubContent.subviews.forEach { $0.removeFromSuperview() }
                hubContent.frame = hub.bounds
                hub.contentView = hubContent
                if hub.superview == nil { addSubview(hub, positioned: .above, relativeTo: disc) }
                hub.isHidden = false
                host = hubContent
                hc = NSPoint(x: lensR, y: lensR)
            } else {
                hub.isHidden = true
                host = content
                hc = c
            }
            for l in [nameLabel, subLabel] {
                l.removeFromSuperview()
                l.alignment = .center
                l.lineBreakMode = .byTruncatingTail
                host.addSubview(l)
            }
            nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            nameLabel.textColor = .labelColor
            subLabel.font = .systemFont(ofSize: 12)
            subLabel.textColor = .secondaryLabelColor
            nameLabel.frame = NSRect(x: hc.x - w / 2, y: hc.y - 1, width: w, height: 21)
            subLabel.frame = NSRect(x: hc.x - w / 2, y: hc.y - 21, width: w, height: 16)
        } else {
            // 蜂窝：正中是图标，名称改用图标上方的小玻璃标签
            hub.isHidden = true
            nameLabel.removeFromSuperview()
            subLabel.removeFromSuperview()
            nameTag.style = .regular
            if s.glassStyle == .dock { DockGlass.applyDockMaterial(nameTag) }
            nameTag.tintColor = nil
            let tc = NSView()
            tagLabel.removeFromSuperview()
            tagLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            tagLabel.textColor = .labelColor
            tagLabel.alignment = .center
            tagLabel.lineBreakMode = .byTruncatingTail
            tc.addSubview(tagLabel)
            nameTag.contentView = tc
            if nameTag.superview == nil { addSubview(nameTag) }
            nameTag.isHidden = true
        }
    }

    /// 窗口显示出来之后再做一次（玻璃要在窗口里才会取样激活状态）
    func refreshGlass() {
        guard AppSettings.shared.glassStyle == .dock else { return }
        DockGlass.finish(glasses + (layout == .grid ? [nameTag] : []))
    }

    private func circle(_ c: NSPoint, _ r: CGFloat) -> NSRect {
        NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    private func iconRect(_ p: NSPoint, scale: CGFloat, big: Bool) -> NSRect {
        circle(p, (big ? iconSize * 1.14 : iconSize) * scale / 2)
    }

    private func setIcon(_ i: Int, big: Bool) {
        guard slots.indices.contains(i) else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            slots[i].icon.animator().frame = iconRect(slots[i].center, scale: slots[i].scale, big: big)
        }
    }

    /// 光圈：第一次出现时淡入，之后在图标之间滑动
    private func moveHighlight(from old: Int?) {
        guard let s = selected else {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; highlight.animator().alphaValue = 0 }
            return
        }
        let r = layout == .ring ? iconSize / 2 + 18 : iconSize * slots[s].scale / 2 + 10
        let target = circle(slots[s].center, r)
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

    private func status(_ it: DockItem) -> String {
        it.isRunning ? (it.isPinned ? L("运行中", "Running") : L("运行中 · 未固定", "Running · Not in Dock")) : L("未运行", "Not running")
    }

    private func updateLabels() {
        if layout == .ring {
            if let s = selected {
                nameLabel.stringValue = slots[s].item.name
                subLabel.stringValue = status(slots[s].item)
            } else {
                nameLabel.stringValue = slots.isEmpty ? L("Dock 上没有 App", "No apps in Dock") : L("\(slots.count) 个 App", "\(slots.count) apps")
                subLabel.stringValue = L("指向图标，点击打开", "Point at an icon, click to open")
            }
            return
        }
        // 蜂窝：名称标签贴在选中图标的上方
        guard let s = selected else { nameTag.isHidden = true; return }
        let sl = slots[s]
        tagLabel.stringValue = sl.item.name
        let w = min(220, max(60, tagLabel.intrinsicContentSize.width + 22)), h: CGFloat = 24
        let top = NSPoint(x: origin.x + sl.center.x, y: origin.y + sl.center.y + iconSize * sl.scale * 0.57 + 6)
        var x = top.x - w / 2
        x = min(max(x, 2), bounds.width - w - 2)
        nameTag.frame = NSRect(x: x, y: min(top.y, bounds.height - h - 2), width: w, height: h)
        nameTag.cornerRadius = h / 2
        tagLabel.frame = NSRect(x: 8, y: 4, width: w - 16, height: 16)
        if nameTag.isHidden {
            nameTag.isHidden = false
            if AppSettings.shared.glassStyle == .dock { DockGlass.finish([nameTag]) }
        }
    }

    // MARK: 鼠标

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }

    private func slot(at viewPoint: NSPoint) -> Int? {
        guard !slots.isEmpty else { return nil }
        let p = NSPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y)   // 换到玻璃内容坐标
        let dx = p.x - R, dy = p.y - R
        let d = hypot(dx, dy)
        if layout == .grid {
            // 蜂窝：选鼠标下面（或最近）的图标
            guard d <= R else { return nil }
            let best = slots.indices.min { hypot(slots[$0].center.x - p.x, slots[$0].center.y - p.y) < hypot(slots[$1].center.x - p.x, slots[$1].center.y - p.y) }!
            return hypot(slots[best].center.x - p.x, slots[best].center.y - p.y) <= cell * 0.62 ? best : nil
        }
        guard d > deadZone, d <= R else { return nil }
        let a = atan2(dy, dx)
        func diff(_ x: CGFloat) -> CGFloat {
            var t = abs(x - a).truncatingRemainder(dividingBy: 2 * .pi)
            if t > .pi { t = 2 * .pi - t }
            return t
        }
        // 一圈：图标等间距、没有空位，指向哪个方向就选离它最近的图标
        return slots.indices.min(by: { diff(slots[$0].angle) < diff(slots[$1].angle) })
    }

    override func mouseMoved(with event: NSEvent) { selected = slot(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { selected = nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let s = slot(at: p) {
            onLaunch?(slots[s].item)
        } else if layout == .ring, hypot(p.x - origin.x - R, p.y - origin.y - R) <= deadZone {
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
