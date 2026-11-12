import AppKit
import SwiftUI
import ServiceManagement

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: .shared)))
            w.title = "DockDot 设置"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 960, height: 640))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 根视图

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            AppearanceTab(settings: settings)
                .tabItem { Label("外观", systemImage: "circle.circle") }
            GeneralTab(settings: settings)
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 960, height: 640)
    }
}

// MARK: - 外观

enum PreviewBackground: String, CaseIterable, Identifiable {
    case wallpaper, lightDoc, darkDoc, colorful, white
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallpaper: "桌面壁纸"
        case .lightDoc: "浅色文档"
        case .darkDoc: "深色文档"
        case .colorful: "彩色"
        case .white: "纯白"
        }
    }
}

struct AppearanceTab: View {
    @ObservedObject var settings: AppSettings
    @State private var background: PreviewBackground = .lightDoc
    private let sample: [DockItem] = Array(DockReader.items().pinned.prefix(10))

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                Picker("参考背景", selection: $background) {
                    ForEach(PreviewBackground.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // 背景放在 background 里：再长的文档也不会把页面撑高
                RadialPreview(settings: settings, items: sample)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(alignment: .top) { PreviewBackgroundView(kind: background) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))

                Text("预览可以直接把鼠标移上去试选中效果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Form {
                Section("液态玻璃") {
                    Picker("样式", selection: $settings.glassStyle) {
                        ForEach(AppSettings.GlassStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.glassStyle == .clear
                         ? "透明：和桌面小组件一样能看到背后，靠着色压住杂乱背景"
                         : "常规：系统按背后内容自动调明暗和模糊，更稳但更实")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("着色", isOn: $settings.tintEnabled)
                    TintPalette(color: $settings.tintColor)
                        .disabled(!settings.tintEnabled)
                        .opacity(settings.tintEnabled ? 1 : 0.4)
                    SliderRow(title: "着色强度", value: $settings.tintAlpha, range: 0...0.6) { "\(Int($0 * 100))%" }
                        .disabled(!settings.tintEnabled)
                    Toggle("悬停 / 按下时玻璃有反应", isOn: $settings.interactive)
                }
                Section("布局") {
                    SliderRow(title: "图标大小", value: $settings.iconSize, range: 36...64, step: 1) { "\(Int($0)) pt" }
                    SliderRow(title: "图标离边缘", value: $settings.edgeMargin, range: 16...64, step: 1) { "\(Int($0)) pt" }
                }
                Section("细节") {
                    Toggle("圆心玻璃（让中间文字更清楚）", isOn: $settings.showCenterLens)
                    SliderRow(title: "选中光晕", value: $settings.highlightStrength, range: 0...0.3) { "\(Int($0 * 100))%" }
                    Toggle("运行中的小点", isOn: $settings.showRunningDots)
                }
                Section {
                    Button("恢复默认外观") { settings.resetAppearance() }
                }
            }
            .formStyle(.grouped)
            .frame(width: 360)
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String

    init(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double? = nil,
         format: @escaping (Double) -> String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }
}

/// 内置调色盘：常用色块 + 色相条 + 明暗，不弹系统颜色窗口
struct TintPalette: View {
    @Binding var color: NSColor

    private static let presets: [NSColor] = [
        .black, NSColor(white: 0.5, alpha: 1), .white,
        NSColor(srgbRed: 0.20, green: 0.48, blue: 1.00, alpha: 1),   // 蓝
        NSColor(srgbRed: 0.35, green: 0.34, blue: 0.84, alpha: 1),   // 靛
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1),   // 紫
        NSColor(srgbRed: 1.00, green: 0.18, blue: 0.47, alpha: 1),   // 粉
        NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1),   // 红
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),   // 橙
        NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1),   // 黄
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),   // 绿
        NSColor(srgbRed: 0.19, green: 0.69, blue: 0.78, alpha: 1),   // 青
    ]

    private var hsb: (h: CGFloat, s: CGFloat, b: CGFloat) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        return (c.hueComponent, c.saturationComponent, c.brightnessComponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("着色颜色")
                Spacer()
                Circle().fill(Color(nsColor: color)).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, p in
                    let selected = Self.same(p, color)
                    Circle().fill(Color(nsColor: p)).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3).opacity(selected ? 1 : 0))
                        .contentShape(Circle())
                        .onTapGesture { color = p }
                }
            }
            HueBar(hue: Binding(
                get: { Double(hsb.h) },
                set: { h in
                    // 从黑白灰拖到色相条时给一个合适的饱和度和亮度
                    let s = hsb.s < 0.15 ? 0.75 : hsb.s
                    let b = hsb.b < 0.2 ? 0.9 : hsb.b
                    color = NSColor(hue: CGFloat(h), saturation: s, brightness: b, alpha: 1)
                }))
            HStack(spacing: 8) {
                Text("明暗").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(hsb.b) },
                    set: { color = NSColor(hue: hsb.h, saturation: hsb.s, brightness: CGFloat($0), alpha: 1) }),
                       in: 0...1)
            }
        }
    }

    private static func same(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) < 0.01 && abs(x.greenComponent - y.greenComponent) < 0.01
            && abs(x.blueComponent - y.blueComponent) < 0.01
    }
}

/// 彩虹色相条，拖动/点击选色相
struct HueBar: View {
    @Binding var hue: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 0.8, brightness: 0.95) },
                    startPoint: .leading, endPoint: .trailing))
                Circle().fill(.white).frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .offset(x: CGFloat(hue) * (w - 16))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                hue = min(max(Double((v.location.x - 8) / (w - 16)), 0), 1)
            })
        }
        .frame(height: 16)
    }
}

/// 把真正的 RadialView 放进 SwiftUI，参数一改就重新布局
struct RadialPreview: NSViewRepresentable {
    @ObservedObject var settings: AppSettings
    let items: [DockItem]

    func makeNSView(context: Context) -> PreviewHost { PreviewHost() }
    func updateNSView(_ v: PreviewHost, context: Context) { v.reload(items) }
}

final class PreviewHost: NSView {
    private let radial = RadialView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        radial.isPreview = true
        addSubview(radial)
    }
    required init?(coder: NSCoder) { fatalError() }

    func reload(_ items: [DockItem]) {
        _ = radial.configure(pinned: items, running: [])
        centerRadial()
    }

    override func layout() {
        super.layout()
        centerRadial()
    }

    private func centerRadial() {
        radial.setFrameOrigin(NSPoint(x: (bounds.width - radial.frame.width) / 2,
                                      y: (bounds.height - radial.frame.height) / 2))
    }
}

// MARK: - 参考背景

struct PreviewBackgroundView: View {
    let kind: PreviewBackground

    var body: some View {
        switch kind {
        case .wallpaper:
            if let img = Self.wallpaper {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ColorfulBackground()
            }
        case .lightDoc: DocumentMock(dark: false)
        case .darkDoc: DocumentMock(dark: true)
        case .colorful: ColorfulBackground()
        case .white: Color.white
        }
    }

    static let wallpaper: NSImage? = {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }()
}

private struct ColorfulBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .purple, .pink, .orange],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.cyan.opacity(0.7)).frame(width: 260).offset(x: -160, y: -120).blur(radius: 30)
            Circle().fill(.yellow.opacity(0.6)).frame(width: 220).offset(x: 170, y: 140).blur(radius: 30)
            Circle().fill(.mint.opacity(0.6)).frame(width: 160).offset(x: 120, y: -170).blur(radius: 20)
        }
    }
}

/// 模拟一个文字很多的窗口，用来看玻璃压在杂乱内容上的效果
private struct DocumentMock: View {
    let dark: Bool

    private let paragraphs = [
        "液态玻璃会根据背后的内容实时折射和调整明暗，所以同一个效果在不同背景上看起来差别很大。",
        "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.",
        "本周进展：完成设置页设计评审；修复快捷键在全屏 App 下偶发失效的问题；优化图标加载速度。",
        "Q4 roadmap · Growth · Foundation · Enterprise — 12 tickets in review, 3 blocked, 27 done.",
        "下一步计划：补充埋点、整理验收用例、和研发对齐上线时间，周五前给出排期。",
    ]

    var body: some View {
        let fg: Color = dark ? .white.opacity(0.85) : .black.opacity(0.8)
        let sub: Color = dark ? .white.opacity(0.5) : .black.opacity(0.45)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 11) }
                Spacer()
                Text("周报 - 产品团队").font(.system(size: 12, weight: .semibold)).foregroundStyle(sub)
                Spacer()
            }
            Text("产品周报").font(.system(size: 26, weight: .bold)).foregroundStyle(fg)
            ForEach(0..<4, id: \.self) { block in
                Text(["进展", "风险", "数据", "计划"][block]).font(.system(size: 16, weight: .semibold)).foregroundStyle(fg)
                ForEach(0..<3, id: \.self) { i in
                    Text(paragraphs[(block * 3 + i) % paragraphs.count])
                        .font(.system(size: 13)).foregroundStyle(i == 2 ? sub : fg)
                }
                HStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule().fill([Color.blue, .green, .orange, .pink, .teal][i].opacity(0.25))
                            .frame(width: CGFloat(50 + i * 14), height: 18)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(dark ? Color(white: 0.12) : Color.white)
    }
}

// MARK: - 通用

struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var axTrusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("小圆点") {
                Toggle("显示屏幕边缘的小圆点", isOn: $settings.dotVisible)
                SliderRow(title: "不用时的透明度", value: $settings.dotIdleAlpha, range: 0.15...1) { "\(Int($0 * 100))%" }
            }
            Section("快捷键") {
                LabeledContent("打开 / 收起面板", value: "按一下 ⌥⌘")
                Text("按住 ⌥⌘ 时按了别的键或点了鼠标（比如 ⌥⌘D、⌥⌘ 拖动）不会触发。面板里也可以用 ← → 选、回车打开、Esc 关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("权限") {
                LabeledContent("辅助功能") {
                    HStack(spacing: 6) {
                        Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(axTrusted ? .green : .orange)
                        Text(axTrusted ? "已授权" : "未授权，⌥⌘ 快捷键不可用")
                    }
                }
                Button("打开系统设置中的辅助功能…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            Section("启动") {
                Toggle("开机自动启动", isOn: Binding(
                    get: { loginEnabled },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        loginEnabled = SMAppService.mainApp.status == .enabled
                    }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        axTrusted = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}
