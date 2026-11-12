import AppKit

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
    }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }   // Esc
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class ItemCell: NSView {
    static let w: CGFloat = 78, h: CGFloat = 84
    let item: DockItem
    var onClick: ((DockItem) -> Void)?
    var onHover: ((ItemCell) -> Void)?

    var highlighted = false {
        didSet { layer?.backgroundColor = highlighted ? NSColor.white.withAlphaComponent(0.18).cgColor : nil }
    }

    init(item: DockItem, origin: NSPoint) {
        self.item = item
        super.init(frame: NSRect(origin: origin, size: NSSize(width: Self.w, height: Self.h)))
        wantsLayer = true
        layer?.cornerRadius = 12
        toolTip = item.name

        let iv = NSImageView(frame: NSRect(x: (Self.w - 52) / 2, y: 6, width: 52, height: 52))
        iv.image = item.icon
        iv.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iv)

        if item.isRunning {
            let d = NSView(frame: NSRect(x: Self.w / 2 - 2, y: 60, width: 4, height: 4))
            d.wantsLayer = true
            d.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            d.layer?.cornerRadius = 2
            addSubview(d)
        }

        let label = NSTextField(labelWithString: item.name)
        label.frame = NSRect(x: 3, y: 65, width: Self.w - 6, height: 16)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {   // 子视图不吃事件
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(self) }
    override func mouseExited(with event: NSEvent) { highlighted = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?(item) }
    }
}

enum Anchor {
    case mouse
    case dot(NSRect, Edge)
}

final class LauncherController {
    private let panel = LauncherPanel()
    private let effect = NSVisualEffectView()
    private let content = FlippedView()
    private var cells: [ItemCell] = []
    private var outsideClickMonitor: Any?

    private let maxCols = 7
    private let pad: CGFloat = 14
    private let gap: CGFloat = 10

    var isVisible: Bool { panel.isVisible }

    init() {
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = effect
        effect.addSubview(content)
        panel.onCancel = { [weak self] in self?.close() }
    }

    func show(anchor: Anchor) {
        rebuild()
        position(anchor)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
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

    /// 快捷键松开：鼠标停在哪个图标上就打开哪个；没停在图标上则面板保持打开，可以再点
    func hotkeyReleased() {
        guard panel.isVisible else { return }
        let p = NSEvent.mouseLocation
        if let cell = cells.first(where: { panel.convertToScreen($0.convert($0.bounds, to: nil)).contains(p) }) {
            launch(cell.item)
        }
    }

    private func launch(_ item: DockItem) {
        close()
        DockReader.open(item)
    }

    private func rebuild() {
        cells.forEach { $0.removeFromSuperview() }
        cells = []
        content.subviews.forEach { $0.removeFromSuperview() }

        let (pinned, running) = DockReader.items()
        let cols = max(1, min(maxCols, max(pinned.count, running.count)))
        let rowsP = Int(ceil(Double(pinned.count) / Double(cols)))
        let rowsR = Int(ceil(Double(running.count) / Double(cols)))

        let width = pad * 2 + CGFloat(cols) * ItemCell.w
        var y = pad
        func place(_ items: [DockItem]) {
            for (i, it) in items.enumerated() {
                let o = NSPoint(x: pad + CGFloat(i % cols) * ItemCell.w, y: y + CGFloat(i / cols) * ItemCell.h)
                let c = ItemCell(item: it, origin: o)
                c.onClick = { [weak self] in self?.launch($0) }
                c.onHover = { [weak self] hovered in self?.cells.forEach { $0.highlighted = ($0 === hovered) } }
                content.addSubview(c)
                cells.append(c)
            }
        }
        place(pinned)
        y += CGFloat(rowsP) * ItemCell.h
        if !running.isEmpty {
            if !pinned.isEmpty {
                y += gap
                let line = NSView(frame: NSRect(x: pad + 6, y: y, width: width - pad * 2 - 12, height: 1))
                line.wantsLayer = true
                line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
                content.addSubview(line)
                y += 1 + gap
            }
            place(running)
            y += CGFloat(rowsR) * ItemCell.h
        }
        if pinned.isEmpty && running.isEmpty {
            let l = NSTextField(labelWithString: "Dock 上没有 App")
            l.textColor = .white
            l.frame = NSRect(x: pad, y: pad, width: 160, height: 20)
            content.addSubview(l)
            y += 20
        }
        let size = NSSize(width: max(width, 190), height: y + pad)
        panel.setContentSize(size)
        content.frame = NSRect(origin: .zero, size: size)
        effect.maskImage = roundedMask(size: size, radius: 20)
    }

    private func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
        let img = NSImage(size: size, flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    private func position(_ anchor: Anchor) {
        let s = panel.frame.size
        var o: NSPoint
        let ref: NSPoint
        switch anchor {
        case .mouse:
            ref = NSEvent.mouseLocation
            o = NSPoint(x: ref.x - s.width / 2, y: ref.y - s.height / 2)
        case let .dot(r, edge):
            ref = NSPoint(x: r.midX, y: r.midY)
            let g: CGFloat = 10
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
