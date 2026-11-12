import AppKit
import Combine

/// 所有可调参数，存在 UserDefaults（local.dockdot）。改动后发 `AppSettings.changed` 通知。
@available(macOS 26.0, *)
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let changed = Notification.Name("DockDotSettingsChanged")

    enum GlassStyle: String, CaseIterable, Identifiable {
        case clear, regular
        var id: String { rawValue }
        var title: String { self == .clear ? L("透明", "Clear") : L("常规", "Regular") }
    }

    // 液态玻璃
    @Published var glassStyle: GlassStyle = .clear { didSet { save() } }
    @Published var tintEnabled = true { didSet { save() } }
    @Published var tintColor: NSColor = .black { didSet { save() } }
    @Published var tintAlpha: Double = 0.11 { didSet { save() } }
    @Published var interactive = true { didSet { save() } }
    // 布局
    @Published var iconSize: Double = 64 { didSet { save() } }
    @Published var edgeMargin: Double = 22 { didSet { save() } }
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
        if let v = d.object(forKey: "iconSize") as? Double { iconSize = v }
        if let v = d.object(forKey: "edgeMargin") as? Double { edgeMargin = v }
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
        d.set(iconSize, forKey: "iconSize")
        d.set(edgeMargin, forKey: "edgeMargin")
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
        glassStyle = .clear
        tintEnabled = true
        tintColor = .black
        tintAlpha = 0.11
        interactive = true
        iconSize = 64
        edgeMargin = 22
        showCenterLens = true
        highlightStrength = 0.21
        showRunningDots = true
        dotIdleAlpha = 0.45
        loading = false
        save()
    }

    /// 实际给玻璃用的着色
    var effectiveTint: NSColor? {
        tintEnabled && tintAlpha > 0 ? tintColor.withAlphaComponent(tintAlpha) : nil
    }
}
