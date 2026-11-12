import AppKit
import Combine

/// 所有可调参数，存在 UserDefaults（local.dockdot）。改动后发 `AppSettings.changed` 通知。
@available(macOS 26.0, *)
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let changed = Notification.Name("DockDotSettingsChanged")

    enum GlassStyle: String, CaseIterable, Identifiable {
        case dock, clear, regular
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dock: L("程序坞", "Dock")
            case .clear: L("透明", "Clear")
            case .regular: L("常规", "Regular")
            }
        }
    }

    // 液态玻璃
    @Published var glassStyle: GlassStyle = .dock { didSet { save() } }
    @Published var tintEnabled = false { didSet { save() } }
    @Published var tintColor: NSColor = .black { didSet { save() } }
    @Published var tintAlpha: Double = 0.11 { didSet { save() } }
    @Published var interactive = true { didSet { save() } }
    // 布局
    enum DiscShape: String, CaseIterable, Identifiable {
        case ring, disc
        var id: String { rawValue }
        var title: String { self == .ring ? L("圆环", "Ring") : L("圆盘", "Disc") }
    }
    @Published var discShape: DiscShape = .ring { didSet { save() } }
    /// 排列方式：自动（App 少用一圈，多了用蜂窝）、强制一圈、强制蜂窝
    enum LayoutMode: String, CaseIterable, Identifiable {
        case auto, ring, grid
        var id: String { rawValue }
        var title: String {
            switch self {
            case .auto: L("自动", "Automatic")
            case .ring: L("一圈", "Single ring")
            case .grid: L("蜂窝", "Honeycomb")
            }
        }
    }
    @Published var layoutMode: LayoutMode = .auto { didSet { save() } }
    /// 自动模式下，App 超过这个数量就改用蜂窝
    @Published var gridThreshold: Int = 14 { didSet { save() } }
    @Published var iconSize: Double = 64 { didSet { save() } }
    @Published var edgeMargin: Double = 22 { didSet { save() } }
    // 玻璃扭曲程度（0…1）：外圈默认和系统 Dock 一样；圆心默认是设置里对比过的方案 4
    @Published var outerDistortion: Double = 0.05 { didSet { save() } }
    @Published var centerDistortion: Double = 0.5 { didSet { save() } }
    // 圆心玻璃：样式和着色独立于外圈
    @Published var centerStyle: GlassStyle = .clear { didSet { save() } }
    @Published var centerTintEnabled = false { didSet { save() } }
    @Published var centerTintColor: NSColor = .white { didSet { save() } }
    @Published var centerTintAlpha: Double = 0.15 { didSet { save() } }
    /// 圆心玻璃边缘的羽化宽度（占半径的比例，0 = 硬边）
    @Published var centerFeather: Double = 0.15 { didSet { save() } }
    // 细节
    @Published var showCenterLens = true { didSet { save() } }
    @Published var highlightStrength: Double = 0.21 { didSet { save() } }
    @Published var showRunningDots = true { didSet { save() } }
    // 语言
    @Published var language: AppLanguage = Lang.setting { didSet { save() } }
    // 小圆点
    @Published var dotVisible = true { didSet { save() } }
    @Published var dotIdleAlpha: Double = 0.45 { didSet { save() } }

    private let d = UserDefaults.standard
    private var loading = false

    private init() { load() }

    private func load() {
        loading = true
        defer { loading = false }
        if let s = d.string(forKey: "glassStyle"), let g = GlassStyle(rawValue: s) { glassStyle = g }
        if let t = d.string(forKey: "glassTint") {          // 兼容旧的 defaults 写法
            tintEnabled = t != "none"
            if t == "black" { tintColor = .black }
        }
        if d.object(forKey: "tintEnabled") != nil { tintEnabled = d.bool(forKey: "tintEnabled") }
        if let c = d.array(forKey: "tintRGB") as? [Double], c.count == 3 {
            tintColor = NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
        }
        if let v = d.object(forKey: "glassTintAlpha") as? Double { tintAlpha = v }
        if d.object(forKey: "interactive") != nil { interactive = d.bool(forKey: "interactive") }
        if let s = d.string(forKey: "discShape"), let v = DiscShape(rawValue: s) { discShape = v }
        if let s = d.string(forKey: "layoutMode"), let v = LayoutMode(rawValue: s) { layoutMode = v }
        if d.object(forKey: "gridThreshold") != nil { gridThreshold = d.integer(forKey: "gridThreshold") }
        if let v = d.object(forKey: "iconSize") as? Double { iconSize = v }
        if let v = d.object(forKey: "edgeMargin") as? Double { edgeMargin = v }
        if let v = d.object(forKey: "outerDistortion") as? Double { outerDistortion = v }
        if let v = d.object(forKey: "centerDistortion") as? Double { centerDistortion = v }
        if let v = d.object(forKey: "centerFeather") as? Double { centerFeather = v }
        if let s = d.string(forKey: "centerStyle"), let g = GlassStyle(rawValue: s) { centerStyle = g }
        if d.object(forKey: "centerTintEnabled") != nil { centerTintEnabled = d.bool(forKey: "centerTintEnabled") }
        if let c = d.array(forKey: "centerTintRGB") as? [Double], c.count == 3 {
            centerTintColor = NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 1)
        }
        if let v = d.object(forKey: "centerTintAlpha") as? Double { centerTintAlpha = v }
        if d.object(forKey: "showCenterLens") != nil { showCenterLens = d.bool(forKey: "showCenterLens") }
        if let v = d.object(forKey: "highlightStrength") as? Double { highlightStrength = v }
        if d.object(forKey: "showRunningDots") != nil { showRunningDots = d.bool(forKey: "showRunningDots") }
        if d.object(forKey: "dotHidden") != nil { dotVisible = !d.bool(forKey: "dotHidden") }
        if let v = d.object(forKey: "dotIdleAlpha") as? Double { dotIdleAlpha = v }
    }

    private func save() {
        guard !loading else { return }
        d.set(glassStyle.rawValue, forKey: "glassStyle")
        d.removeObject(forKey: "glassTint")
        d.set(tintEnabled, forKey: "tintEnabled")
        let c = tintColor.usingColorSpace(.sRGB) ?? .black
        d.set([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)], forKey: "tintRGB")
        d.set(tintAlpha, forKey: "glassTintAlpha")
        d.set(interactive, forKey: "interactive")
        d.set(discShape.rawValue, forKey: "discShape")
        d.set(layoutMode.rawValue, forKey: "layoutMode")
        d.set(gridThreshold, forKey: "gridThreshold")
        d.set(iconSize, forKey: "iconSize")
        d.set(edgeMargin, forKey: "edgeMargin")
        d.set(outerDistortion, forKey: "outerDistortion")
        d.set(centerDistortion, forKey: "centerDistortion")
        d.set(centerFeather, forKey: "centerFeather")
        d.set(centerStyle.rawValue, forKey: "centerStyle")
        d.set(centerTintEnabled, forKey: "centerTintEnabled")
        let cc = centerTintColor.usingColorSpace(.sRGB) ?? .white
        d.set([Double(cc.redComponent), Double(cc.greenComponent), Double(cc.blueComponent)], forKey: "centerTintRGB")
        d.set(centerTintAlpha, forKey: "centerTintAlpha")
        d.set(showCenterLens, forKey: "showCenterLens")
        d.set(highlightStrength, forKey: "highlightStrength")
        d.set(showRunningDots, forKey: "showRunningDots")
        d.set(!dotVisible, forKey: "dotHidden")
        d.set(dotIdleAlpha, forKey: "dotIdleAlpha")
        d.set(language.rawValue, forKey: "language")
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    /// 外观参数恢复默认（不动「显示小圆点」）
    func resetAppearance() {
        loading = true
        glassStyle = .dock
        tintEnabled = false
        tintColor = .black
        tintAlpha = 0.11
        interactive = true
        discShape = .ring
        layoutMode = .auto
        gridThreshold = 14
        iconSize = 64
        edgeMargin = 22
        outerDistortion = 0.05
        centerDistortion = 0.5
        centerFeather = 0.15
        centerStyle = .clear
        centerTintEnabled = false
        centerTintColor = .white
        centerTintAlpha = 0.15
        showCenterLens = true
        highlightStrength = 0.21
        showRunningDots = true
        dotIdleAlpha = 0.45
        loading = false
        save()
    }

    /// 按 App 数量算出实际用哪种排列
    func resolvedLayout(appCount n: Int) -> LayoutMode {
        switch layoutMode {
        case .auto: n > gridThreshold ? .grid : .ring
        default: layoutMode
        }
    }

    /// 实际给玻璃用的着色
    /// 程序坞是独立的固定样式：和系统 Dock 一样，不着色
    var effectiveTint: NSColor? {
        guard glassStyle != .dock else { return nil }
        return tintEnabled && tintAlpha > 0 ? tintColor.withAlphaComponent(tintAlpha) : nil
    }

    /// 圆心玻璃实际用的着色（程序坞样式同样不着色）
    var centerEffectiveTint: NSColor? {
        guard centerStyle != .dock else { return nil }
        return centerTintEnabled && centerTintAlpha > 0 ? centerTintColor.withAlphaComponent(centerTintAlpha) : nil
    }

    /// 玻璃对悬停/按下的反馈：程序坞样式不用（系统 Dock 本身没有这种反馈）
    var effectiveInteractive: Bool { glassStyle != .dock && interactive }
}
