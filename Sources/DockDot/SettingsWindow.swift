import AppKit
import SwiftUI
import ServiceManagement

// MARK: - 窗口

/// 设置窗口。打开时把 App 临时切成普通 App（有 Dock 图标和菜单栏），
/// 这样窗口能正常来到最前面、被台前调度当成一个窗口；关掉后再切回菜单栏 App。
@available(macOS 26.0, *)
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(pane: SettingsPane? = nil) {
        if let pane { SettingsNav.shared.pane = pane }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: .shared, nav: .shared)))
            w.title = L("DockDot 设置", "DockDot Settings")
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 1100, height: 720))
            w.delegate = self
            w.center()
            window = w
            NotificationCenter.default.addObserver(forName: AppSettings.changed, object: nil, queue: .main) { [weak w] _ in
                w?.title = L("DockDot 设置", "DockDot Settings")
            }
        }
        NSApp.setActivationPolicy(.regular)
        // 切换成普通 App 需要一个运行循环才生效，下一轮再把窗口带到最前
        DispatchQueue.main.async { [weak self] in
            NSApp.unhide(nil)
            NSApp.activate()
            self?.window?.makeKeyAndOrderFront(nil)
            self?.window?.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        // 稍等一下再切回菜单栏 App，避免关窗动画还没结束 Dock 图标就消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - 导航

@available(macOS 26.0, *)
enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance, general, permissions, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appearance: L("外观", "Appearance")
        case .general: L("通用", "General")
        case .permissions: L("权限", "Permissions")
        case .about: L("关于", "About")
        }
    }
    var subtitle: String {
        switch self {
        case .appearance: L("调整圆盘的液态玻璃、图标和细节。", "Adjust the disc’s Liquid Glass, icons and details.")
        case .general: L("语言、悬浮小圆点、快捷键和启动方式。", "Language, floating dot, shortcut and startup.")
        case .permissions: L("DockDot 需要的系统权限，以及每项权限当前的状态。", "The system permissions DockDot needs and the current status of each.")
        case .about: ""
        }
    }
    var icon: String {
        switch self {
        case .appearance: "circle.circle.fill"
        case .general: "gearshape.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .appearance: .indigo
        case .general: .gray
        case .permissions: .blue
        case .about: .teal
        }
    }
}

@available(macOS 26.0, *)
final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    // 启动参数 --settings-tab <appearance|general|permissions|about> 可以直接打开某一页
    @Published var pane: SettingsPane? = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--settings-tab"), i + 1 < a.count { return SettingsPane(rawValue: a[i + 1]) ?? .appearance }
        return .appearance
    }()
}

/// 彩色圆角方块里的白色图标（和系统设置的侧边栏一致）
@available(macOS 26.0, *)
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

@available(macOS 26.0, *)
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var nav: SettingsNav

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.pane) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("DockDot").font(.system(size: 13, weight: .semibold))
                        Text(L("版本 \(version)", "Version \(version)")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .selectionDisabled()

                ForEach(SettingsPane.allCases) { p in
                    Label { Text(p.title) } icon: { IconTile(symbol: p.icon, tint: p.tint) }
                        .padding(.vertical, 2)
                        .tag(p)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch nav.pane ?? .appearance {
                case .appearance: AppearancePane(settings: settings)
                case .general: GeneralPane(settings: settings)
                case .permissions: PermissionsPane()
                case .about: AboutPane()
                }
            }
            .navigationTitle((nav.pane ?? .appearance).title)
        }
        .frame(minWidth: 1100, minHeight: 720)
    }
}

/// 每一页顶部的标题：图标 + 标题 + 一句说明
@available(macOS 26.0, *)
struct PaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: pane.icon, tint: pane.tint, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(pane.title).font(.system(size: 20, weight: .semibold))
                Text(pane.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .padding(.bottom, 2)
    }
}

/// 左边文字、右边滑块 + 数值
@available(macOS 26.0, *)
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                Group {
                    if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
                }
                .frame(width: 210)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

// MARK: - 外观

@available(macOS 26.0, *)
enum PreviewBackground: String, CaseIterable, Identifiable {
    case wallpaper, lightDoc, darkDoc, colorful, white
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallpaper: L("桌面壁纸", "Wallpaper")
        case .lightDoc: L("浅色页面", "Light page")
        case .darkDoc: L("深色页面", "Dark page")
        case .colorful: L("彩色", "Colorful")
        case .white: L("纯白", "White")
        }
    }
}

@available(macOS 26.0, *)
struct AppearancePane: View {
    @ObservedObject var settings: AppSettings
    @State private var background: PreviewBackground = .lightDoc
    private let sample: [DockItem] = Array(DockReader.items().pinned.prefix(10))

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(pane: .appearance)
            HStack(alignment: .top, spacing: 0) {
                // 左边：固定不动的预览，右边改任何参数都能马上看到效果
                VStack(alignment: .leading, spacing: 14) {
                    RadialPreview(settings: settings, items: sample)
                        .frame(width: 420, height: 440)
                        .background(alignment: .top) { PreviewBackgroundView(kind: background) }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    HStack(spacing: 10) {
                        Text(L("参考背景", "Background")).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        ForEach(PreviewBackground.allCases) { kind in
                            BackgroundChip(kind: kind, selected: kind == background)
                                .onTapGesture { background = kind }
                                .help(kind.title)
                        }
                    }
                    Footnote(L("预览用的是 Dock 里的前 10 个 App，鼠标移到预览上可以试试选中效果。",
                               "The preview uses the first 10 apps in your Dock. Hover over it to try the selection effect."))
                    Spacer(minLength: 0)
                }
                .frame(width: 420)
                .padding(.leading, 30)
                .padding(.top, 18)

                Form {
                Section {
                    LabeledContent(L("样式", "Style")) {
                        Picker(L("样式", "Style"), selection: $settings.glassStyle) {
                            ForEach(AppSettings.GlassStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Toggle(L("着色", "Tint"), isOn: $settings.tintEnabled)
                    if settings.tintEnabled {
                        LabeledContent(L("颜色", "Color")) { SwatchRow(color: $settings.tintColor) }
                        LabeledContent(L("自定义颜色", "Custom color")) { HueBar(color: $settings.tintColor).frame(width: 266) }
                        ValueSlider(title: L("着色强度", "Tint strength"), value: $settings.tintAlpha, range: 0...0.6) { "\(Int($0 * 100))%" }
                    }
                    Toggle(L("悬停和按下时玻璃有反馈", "Glass responds to hover and press"), isOn: $settings.interactive)
                } header: {
                    Text(L("液态玻璃", "Liquid Glass"))
                } footer: {
                    Footnote({
                        switch settings.glassStyle {
                        case .dock: return L("程序坞：和系统程序坞相同的液态玻璃材质，一般不需要着色。",
                                             "Dock: the same Liquid Glass material as the system Dock. Usually no tint needed.")
                        case .clear: return L("透明：和桌面小组件一样能看到背后的内容。背景比较杂时，可以加一点着色让图标更清楚。",
                                              "Clear: see-through, like desktop widgets. On busy backgrounds, a little tint keeps icons clear.")
                        case .regular: return L("常规：系统根据背后的内容自动调整明暗和模糊，更稳定，但会偏白、没那么通透。",
                                                "Regular: the system adapts brightness and blur to what’s behind — steadier, but whiter and less see-through.")
                        }
                    }())
                }

                Section(L("布局", "Layout")) {
                    ValueSlider(title: L("图标大小", "Icon size"), value: $settings.iconSize, range: 36...64, step: 1) { "\(Int($0)) pt" }
                    ValueSlider(title: L("图标与边缘的距离", "Distance from edge"), value: $settings.edgeMargin, range: 16...64, step: 1) { "\(Int($0)) pt" }
                }

                Section {
                    Toggle(L("圆心玻璃", "Center glass"), isOn: $settings.showCenterLens)
                    ValueSlider(title: L("选中光晕", "Selection glow"), value: $settings.highlightStrength, range: 0...0.3) { "\(Int($0 * 100))%" }
                    Toggle(L("显示运行中的小点", "Show running indicators"), isOn: $settings.showRunningDots)
                } header: {
                    Text(L("细节", "Details"))
                } footer: {
                    Footnote(L("圆心玻璃会把背后的内容模糊掉，让中间的 App 名称在任何背景上都看得清。",
                               "The center glass blurs what’s behind it so the app name stays readable on any background."))
                }

                Section {
                    HStack {
                        Spacer()
                        Button(L("恢复默认外观", "Restore Defaults")) { settings.resetAppearance() }
                    }
                }
                }
                .formStyle(.grouped)
            }
        }
    }
}

/// 分组下方的小号说明文字
@available(macOS 26.0, *)
struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 参考背景的缩略图
@available(macOS 26.0, *)
struct BackgroundChip: View {
    let kind: PreviewBackground
    let selected: Bool

    var body: some View {
        thumbnail
            .frame(width: 44, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2).padding(-3).opacity(selected ? 1 : 0))
            .contentShape(Rectangle())
    }

    @ViewBuilder private var thumbnail: some View {
        switch kind {
        case .wallpaper:
            if let img = PreviewBackgroundView.wallpaper { Image(nsImage: img).resizable().scaledToFill() } else { ColorfulBackground() }
        case .lightDoc, .darkDoc:
            let dark = kind == .darkDoc
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill((dark ? Color.white : Color.black).opacity(i == 0 ? 0.55 : 0.25))
                        .frame(width: i == 0 ? 20 : CGFloat(30 - i * 3), height: i == 0 ? 3 : 2)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(dark ? Color(white: 0.13) : Color.white)
        case .colorful: ColorfulBackground()
        case .white: Color.white
        }
    }
}

/// 常用颜色色块
@available(macOS 26.0, *)
struct SwatchRow: View {
    @Binding var color: NSColor

    static let presets: [NSColor] = [
        .black, NSColor(white: 0.55, alpha: 1), .white,
        NSColor(srgbRed: 0.20, green: 0.48, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.18, blue: 0.47, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
        NSColor(srgbRed: 0.19, green: 0.69, blue: 0.78, alpha: 1),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, p in
                Circle().fill(Color(nsColor: p)).frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3).opacity(Self.same(p, color) ? 1 : 0))
                    .contentShape(Circle())
                    .onTapGesture { color = p }
            }
        }
    }

    static func same(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) < 0.01 && abs(x.greenComponent - y.greenComponent) < 0.01
            && abs(x.blueComponent - y.blueComponent) < 0.01
    }
}

/// 自定义颜色：上面一条色相，下面一条明暗（都是内置控件，不弹系统颜色窗口）
@available(macOS 26.0, *)
struct HueBar: View {
    @Binding var color: NSColor

    private var hsb: (h: CGFloat, s: CGFloat, b: CGFloat) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        return (c.hueComponent, c.saturationComponent, c.brightnessComponent)
    }

    var body: some View {
        VStack(spacing: 8) {
            track(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 0.8, brightness: 0.95) },
                                 startPoint: .leading, endPoint: .trailing),
                  value: Double(hsb.h)) { h in
                // 从黑白灰直接拖到色相条时，给一个合适的饱和度和亮度
                let s = hsb.s < 0.15 ? 0.75 : hsb.s
                let b = hsb.b < 0.2 ? 0.9 : hsb.b
                color = NSColor(hue: CGFloat(h), saturation: s, brightness: b, alpha: 1)
            }
            track(LinearGradient(colors: [.black, Color(hue: Double(hsb.h), saturation: Double(max(hsb.s, 0.0)), brightness: 1)],
                                 startPoint: .leading, endPoint: .trailing),
                  value: Double(hsb.b)) { b in
                color = NSColor(hue: hsb.h, saturation: hsb.s, brightness: CGFloat(b), alpha: 1)
            }
        }
    }

    private func track(_ fill: LinearGradient, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(fill).overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                Circle().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .offset(x: CGFloat(value) * (w - 14))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                onChange(min(max(Double((v.location.x - 7) / (w - 14)), 0), 1))
            })
        }
        .frame(height: 14)
    }
}

/// 把真正的 RadialView 放进 SwiftUI，参数一改就重新布局
@available(macOS 26.0, *)
struct RadialPreview: NSViewRepresentable {
    @ObservedObject var settings: AppSettings
    let items: [DockItem]

    func makeNSView(context: Context) -> PreviewHost { PreviewHost() }
    func updateNSView(_ v: PreviewHost, context: Context) { v.reload(items) }
}

@available(macOS 26.0, *)
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

@available(macOS 26.0, *)
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

@available(macOS 26.0, *)
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

/// 一个文字很多的页面，用来看玻璃压在杂乱内容上的效果（文字随界面语言变化）
@available(macOS 26.0, *)
private struct DocumentMock: View {
    let dark: Bool

    private var paragraphs: [String] {
        Lang.isChinese ? [
            "液态玻璃会根据背后的内容实时折射光线、调整明暗，所以同一组设置放在不同的背景上，看起来会很不一样。",
            "浅色页面和大量文字是最考验玻璃的场景：背后的字和图标叠在一起，容易显得杂乱。",
            "适当加一点着色、或者打开圆心玻璃，可以让图标和名称在这种背景上依然清楚。",
            "The quick brown fox jumps over the lazy dog. Sphinx of black quartz, judge my vow.",
        ] : [
            "Liquid Glass refracts light and adapts its brightness to whatever is behind it, so the same settings can look very different on different backgrounds.",
            "Light pages full of text are the toughest case: text behind the glass competes with the icons on top.",
            "A little tint, or the center glass, keeps icons and labels clear even on backgrounds like this.",
            "The quick brown fox jumps over the lazy dog. Sphinx of black quartz, judge my vow.",
        ]
    }

    var body: some View {
        let fg: Color = dark ? .white.opacity(0.85) : .black.opacity(0.82)
        let sub: Color = dark ? .white.opacity(0.5) : .black.opacity(0.45)
        VStack(alignment: .leading, spacing: 10) {
            Text(L("液态玻璃", "Liquid Glass")).font(.system(size: 26, weight: .bold)).foregroundStyle(fg)
            Text(L("关于材质、光线和可读性", "On material, light and legibility")).font(.system(size: 13)).foregroundStyle(sub)
            ForEach(0..<3, id: \.self) { block in
                ForEach(0..<paragraphs.count, id: \.self) { i in
                    Text(paragraphs[(block + i) % paragraphs.count])
                        .font(.system(size: 13)).foregroundStyle(i == 3 ? sub : fg)
                }
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 6)
                            .fill([Color.blue, .orange, .green][(block + i) % 3].opacity(0.22))
                            .frame(height: 46)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(dark ? Color(white: 0.12) : Color.white)
    }
}

// MARK: - 通用

@available(macOS 26.0, *)
struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(pane: .general)
            Form {
                Section(L("语言", "Language")) {
                    Picker(L("界面语言", "Interface language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Toggle(L("在屏幕边缘显示小圆点", "Show the dot at the screen edge"), isOn: $settings.dotVisible)
                    ValueSlider(title: L("闲置时的透明度", "Opacity when idle"), value: $settings.dotIdleAlpha, range: 0.15...1) { "\(Int($0 * 100))%" }
                        .disabled(!settings.dotVisible)
                } header: {
                    Text(L("悬浮小圆点", "Floating Dot"))
                } footer: {
                    Footnote(L("小圆点可以拖到任意位置，松手后会吸附到最近的屏幕边缘。",
                               "Drag the dot anywhere; it snaps to the nearest screen edge."))
                }
                Section {
                    LabeledContent(L("打开或收起面板", "Open or close the panel")) {
                        HStack(spacing: 6) {
                            KeyCap("⌥")
                            KeyCap("⌘")
                            Text(L("单按一下", "tap")).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent(L("在面板中", "In the panel")) {
                        Text(L("← → 选择 · 回车打开 · Esc 关闭", "← → select · Return open · Esc close")).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L("快捷键", "Shortcut"))
                } footer: {
                    Footnote(L("按住 ⌥⌘ 的同时按了其他键或点了鼠标（例如 ⌥⌘D、⌥⌘ 拖动），不会触发。",
                               "Holding ⌥⌘ while pressing another key or clicking (e.g. ⌥⌘D, ⌥⌘-drag) won’t trigger it."))
                }
                Section {
                    Toggle(L("登录时自动打开", "Open at login"), isOn: Binding(
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
                } header: {
                    Text(L("启动", "Startup"))
                } footer: {
                    if let loginError { Footnote(loginError).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { loginEnabled = SMAppService.mainApp.status == .enabled }
    }
}

@available(macOS 26.0, *)
struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .medium))
            .frame(minWidth: 22, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

// MARK: - 权限

@available(macOS 26.0, *)
enum PermissionState {
    case granted, notGranted, off, needsApproval, unused
    var label: String {
        switch self {
        case .granted: L("已授权", "Granted")
        case .notGranted: L("未授权", "Not granted")
        case .off: L("未开启", "Off")
        case .needsApproval: L("待允许", "Needs approval")
        case .unused: L("不使用", "Not used")
        }
    }
    var color: Color {
        switch self {
        case .granted: .green
        case .notGranted, .needsApproval: .orange
        case .off, .unused: .secondary
        }
    }
    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .notGranted, .needsApproval: "exclamationmark.circle.fill"
        case .off, .unused: "minus.circle.fill"
        }
    }
}

@available(macOS 26.0, *)
struct StatusBadge: View {
    let state: PermissionState
    var body: some View {
        Label(state.label, systemImage: state.symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(state.color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(state.color.opacity(0.12)))
    }
}

/// 一项权限：图标、名称、是否必需、用途、状态和操作按钮
@available(macOS 26.0, *)
struct PermissionItem<Actions: View>: View {
    let symbol: String
    let tint: Color
    let name: String
    let requirement: String
    let purpose: String
    let state: PermissionState
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: symbol, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 13, weight: .semibold))
                    Text(requirement)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.5))
                }
                Text(purpose).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { actions() }.controlSize(.small).padding(.top, 2)
            }
            Spacer(minLength: 8)
            StatusBadge(state: state)
        }
        .padding(.vertical, 4)
    }
}

@available(macOS 26.0, *)
struct PermissionsPane: View {
    @ObservedObject private var settings = AppSettings.shared   // 切换语言时刷新
    @State private var ax = AXIsProcessTrusted()
    @State private var input = CGPreflightListenEventAccess()
    @State private var login = SMAppService.mainApp.status

    private var loginState: PermissionState {
        switch login {
        case .enabled: .granted
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(pane: .permissions)
            Form {
                Section {
                    PermissionItem(symbol: "accessibility", tint: .blue,
                                   name: L("辅助功能", "Accessibility"),
                                   requirement: L("必需", "Required"),
                                   purpose: L("点图标时，把 App 在其他屏幕或其他桌面上的窗口带到前面。",
                                              "Brings an app’s window forward when it’s on another display or Space."),
                                   state: ax ? .granted : .notGranted) {
                        Button(L("打开系统设置", "Open System Settings")) { open("Privacy_Accessibility") }
                        if !ax { Button(L("重新授权", "Re-authorize")) { reauthorize() } }
                    }
                    PermissionItem(symbol: "keyboard", tint: .purple,
                                   name: L("输入监控", "Input Monitoring"),
                                   requirement: L("必需", "Required"),
                                   purpose: L("识别单按一下 ⌥⌘。只判断这两个键有没有被单独按下，不记录、不保存你输入的任何内容。",
                                              "Recognizes a tap of ⌥⌘. It only checks whether those two keys were pressed on their own; nothing you type is recorded or stored."),
                                   state: input ? .granted : .notGranted) {
                        if input {
                            Button(L("打开系统设置", "Open System Settings")) { open("Privacy_ListenEvent") }
                        } else {
                            Button(L("授权…", "Grant Access…")) { _ = CGRequestListenEventAccess(); open("Privacy_ListenEvent") }
                        }
                    }
                    PermissionItem(symbol: "power", tint: .gray,
                                   name: L("登录项", "Login Items"),
                                   requirement: L("可选", "Optional"),
                                   purpose: L("登录 Mac 时自动打开 DockDot。在「通用」里开启。",
                                              "Opens DockDot when you log in. Turn it on under General."),
                                   state: loginState) {
                        Button(L("打开系统设置", "Open System Settings")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                        }
                    }
                } header: {
                    Text(L("需要的权限", "Required Permissions"))
                } footer: {
                    Footnote(L("在系统设置里打开开关后，这里的状态会自动更新。如果开关已经打开、这里仍显示未授权，说明那条授权属于旧版本 DockDot（签名不同），点「重新授权」后按提示重新打开开关即可。",
                               "Statuses update automatically after you turn a switch on in System Settings. If a switch is already on but this still says not granted, that entry belongs to an older DockDot build with a different signature — click Re-authorize and turn the switch on again."))
                }

                Section {
                    LabeledContent(L("屏幕录制、文件与文件夹、通讯录、麦克风、摄像头、定位", "Screen Recording, Files & Folders, Contacts, Microphone, Camera, Location")) {
                        StatusBadge(state: .unused)
                    }
                } header: {
                    Text(L("不需要的权限", "Not Requested"))
                }

                Section {
                    LabeledContent(L("网络", "Network")) { Text(L("不联网，不收集、不上传任何数据", "No network access; no data collected or uploaded")).foregroundStyle(.secondary) }
                    LabeledContent(L("读取的内容", "What it reads")) { Text(L("只读取 Dock 的 App 列表和正在运行的 App", "Only the Dock’s app list and running apps")).foregroundStyle(.secondary) }
                    LabeledContent(L("设置存放", "Settings")) { Text(L("只保存在这台 Mac 上", "Stored only on this Mac")).foregroundStyle(.secondary) }
                } header: {
                    Text(L("隐私", "Privacy"))
                } footer: {
                    Footnote(L("跨桌面切换窗口用到了 macOS 的非公开接口（和 AltTab 相同）。以后的系统更新可能让它失效，届时会退回普通的打开方式。",
                               "Switching to windows on other Spaces uses private macOS APIs (as AltTab does). A future macOS update may break this; DockDot then falls back to opening the app normally."))
                }
            }
            .formStyle(.grouped)
        }
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func refresh() {
        ax = AXIsProcessTrusted()
        input = CGPreflightListenEventAccess()
        login = SMAppService.mainApp.status
    }

    private func open(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    /// 清掉 DockDot 自己的旧授权记录（只影响 DockDot），再弹出系统的授权提示
    private func reauthorize() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "local.dockdot"]
        try? p.run()
        p.waitUntilExit()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        open("Privacy_Accessibility")
    }
}

// MARK: - 关于

@available(macOS 26.0, *)
struct AboutPane: View {
    @ObservedObject private var settings = AppSettings.shared   // 切换语言时刷新
    private static let repo = "https://github.com/mars7233/DockDot"

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                    Text("DockDot").font(.system(size: 22, weight: .semibold))
                    Text(L("版本 \(version)", "Version \(version)")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(L("把 Mac 的 Dock 收进一个小圆点。", "Your Mac’s Dock, tucked into a small dot."))
                        .font(.system(size: 13)).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }

            Section(L("链接", "Links")) {
                LinkRow(title: L("项目主页", "Project page"), detail: "github.com/mars7233/DockDot", url: Self.repo) {
                    GitHubMark().frame(width: 16, height: 16)
                }
                LinkRow(title: L("反馈问题", "Report an issue"), detail: "GitHub Issues", url: Self.repo + "/issues") {
                    Image(systemName: "exclamationmark.bubble")
                }
                LinkRow(title: L("许可证", "License"), detail: "PolyForm Strict 1.0.0", url: Self.repo + "/blob/main/LICENSE") {
                    Image(systemName: "doc.text")
                }
            }

            Section {
                LinkRow(title: "dok", detail: L("液态玻璃轮盘的材质用法", "Using native glass for a radial wheel"),
                        url: "https://github.com/chillintheshade/dok") { Image(systemName: "circle.dashed") }
                LinkRow(title: "AltTab", detail: L("跨桌面切换窗口的做法", "Focusing windows across Spaces"),
                        url: "https://github.com/lwouis/alt-tab-macos") { Image(systemName: "rectangle.on.rectangle") }
                LinkRow(title: "RadialMenu", detail: L("⌥⌘ 快捷键的灵感", "Inspiration for the ⌥⌘ shortcut"),
                        url: "https://github.com/ricky-yosh/RadialMenu") { Image(systemName: "command") }
            } header: {
                Text(L("致谢", "Acknowledgements"))
            } footer: {
                Footnote(L("© 2026 Mason。仅限个人或非营利使用；修改、复制、转发或商业使用需获得作者许可。",
                           "© 2026 Mason. Personal and noncommercial use only; modifying, copying, redistributing or commercial use requires the author’s permission."))
            }
        }
        .formStyle(.grouped)
    }
}

/// 一行链接：图标、标题、说明，右侧箭头
@available(macOS 26.0, *)
struct LinkRow<Icon: View>: View {
    let title: String
    let detail: String
    let url: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 10) {
                icon().frame(width: 18).foregroundStyle(.secondary)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(detail).foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// GitHub 标志（Octicons mark-github），模板图跟随文字颜色
@available(macOS 26.0, *)
struct GitHubMark: View {
    private static let image: NSImage? = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="16" height="16"><path fill="#000" d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"/></svg>
        """
        guard let img = NSImage(data: Data(svg.utf8)) else { return nil }
        img.isTemplate = true
        return img
    }()

    var body: some View {
        if let img = Self.image {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
        }
    }
}
