// 生成 App 图标：swift scripts/make-icon.swift <输出目录>
// 深色圆角方块里，一圈彩色小圆点（代表 Dock 里的 App）围着中间的白色圆点。
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS 图标网格：主体 824/1024，圆角约 22.37%
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.2237
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // 阴影 + 渐变底
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.18, blue: 0.36, alpha: 1),
                        NSColor(srgbRed: 0.07, green: 0.08, blue: 0.16, alpha: 1)])!
        .draw(in: shape, angle: -90)

    let c = NSPoint(x: body.midX, y: body.midY)
    func circle(_ p: NSPoint, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    // 玻璃圆盘
    let discR = body.width * 0.40
    NSColor.white.withAlphaComponent(0.10).setFill()
    circle(c, discR).fill()
    NSColor.white.withAlphaComponent(0.28).setStroke()
    let rim = circle(c, discR)
    rim.lineWidth = s * 0.006
    rim.stroke()

    // 一圈 App 圆点
    let colors: [NSColor] = [
        NSColor(srgbRed: 0.20, green: 0.48, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.18, blue: 0.47, alpha: 1),
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1),
        NSColor(srgbRed: 0.19, green: 0.69, blue: 0.78, alpha: 1),
    ]
    let ringR = discR * 0.70
    let dotR = discR * 0.15
    for (i, col) in colors.enumerated() {
        let a = CGFloat.pi / 2 - 2 * .pi * CGFloat(i) / CGFloat(colors.count)
        let p = NSPoint(x: c.x + ringR * cos(a), y: c.y + ringR * sin(a))
        col.setFill()
        circle(p, dotR).fill()
    }

    // 中间的小圆点（和屏幕边缘的悬浮点同一个样子）
    NSColor.white.withAlphaComponent(0.25).setFill()
    circle(c, discR * 0.30).fill()
    NSColor.white.setFill()
    circle(c, discR * 0.18).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print(iconset.path)
