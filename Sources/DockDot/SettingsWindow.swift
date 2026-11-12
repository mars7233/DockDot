import AppKit
import SwiftUI
import ServiceManagement

@available(macOS 26.0, *)
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: .shared)))
            w.title = L("DockDot 设置", "DockDot Settings")
            // 内容延伸到标题栏下面、标题栏透明：左侧导航栏能一直铺到窗口顶部
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 1100, height: 680))
            w.center()
            window = w
            NotificationCenter.default.addObserver(forName: AppSettings.changed, object: nil, queue: .main) { [weak w] _ in
                w?.title = L("DockDot 设置", "DockDot Settings")
            }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 根视图：左侧导航 + 右侧内容

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
    var icon: String {
        switch self {
        case .appearance: "circle.circle"
        case .general: "gearshape"
        case .permissions: "lock.shield"
        case .about: "info.circle"
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
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    // 启动参数 --settings-tab <appearance|general|permissions|about> 可以直接打开某一页
    @State private var pane: SettingsPane? = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--settings-tab"), i + 1 < a.count { return SettingsPane(rawValue: a[i + 1]) ?? .appearance }
        return .appearance
    }()

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section {
                    ForEach(SettingsPane.allCases) { p in
                        Label {
                            Text(p.title)
                        } icon: {
                            // 和系统设置一样：彩色圆角方块里放白色图标
                            Image(systemName: p.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(p.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .tag(p)
                    }
                } header: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DockDot").font(.headline).foregroundStyle(.primary)
                            Text(L("版本 \(version)", "Version \(version)")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 10)
                    .textCase(nil)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane ?? .appearance {
                case .appearance: AppearanceTab(settings: settings)
                case .general: GeneralTab(settings: settings)
                case .permissions: PermissionsTab()
                case .about: AboutTab()
                }
            }
            .navigationTitle((pane ?? .appearance).title)
        }
        .frame(minWidth: 1100, minHeight: 680)
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
        case .lightDoc: L("浅色文档", "Light Doc")
        case .darkDoc: L("深色文档", "Dark Doc")
        case .colorful: L("彩色", "Colorful")
        case .white: L("纯白", "White")
        }
    }
}

@available(macOS 26.0, *)
struct AppearanceTab: View {
    @ObservedObject var settings: AppSettings
    @State private var background: PreviewBackground = .lightDoc
    private let sample: [DockItem] = Array(DockReader.items().pinned.prefix(10))

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                Picker(L("参考背景", "Reference background"), selection: $background) {
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

                Text(L("预览可以直接把鼠标移上去试选中效果", "Hover over the preview to try the selection effect"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Form {
                Section(L("液态玻璃", "Liquid Glass")) {
                    Picker(L("样式", "Style"), selection: $settings.glassStyle) {
                        ForEach(AppSettings.GlassStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.glassStyle == .clear
                         ? L("透明：和桌面小组件一样能看到背后，靠着色压住杂乱背景", "Clear: see-through like desktop widgets; the tint calms busy backgrounds")
                         : L("常规：系统按背后内容自动调明暗和模糊，更稳但更实", "Regular: the system adapts brightness and blur to what is behind; steadier but more opaque"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(L("着色", "Tint"), isOn: $settings.tintEnabled)
                    TintPalette(color: $settings.tintColor)
                        .disabled(!settings.tintEnabled)
                        .opacity(settings.tintEnabled ? 1 : 0.4)
                    SliderRow(title: L("着色强度", "Tint strength"), value: $settings.tintAlpha, range: 0...0.6) { "\(Int($0 * 100))%" }
                        .disabled(!settings.tintEnabled)
                    Toggle(L("悬停 / 按下时玻璃有反应", "Glass reacts to hover / press"), isOn: $settings.interactive)
                }
                Section(L("布局", "Layout")) {
                    SliderRow(title: L("图标大小", "Icon size"), value: $settings.iconSize, range: 36...64, step: 1) { "\(Int($0)) pt" }
                    SliderRow(title: L("图标离边缘", "Distance from edge"), value: $settings.edgeMargin, range: 16...64, step: 1) { "\(Int($0)) pt" }
                }
                Section(L("细节", "Details")) {
                    Toggle(L("圆心玻璃（让中间文字更清楚）", "Center glass (keeps the label readable)"), isOn: $settings.showCenterLens)
                    SliderRow(title: L("选中光晕", "Selection glow"), value: $settings.highlightStrength, range: 0...0.3) { "\(Int($0 * 100))%" }
                    Toggle(L("运行中的小点", "Running indicators"), isOn: $settings.showRunningDots)
                }
                Section {
                    Button(L("恢复默认外观", "Restore Default Appearance")) { settings.resetAppearance() }
                }
            }
            .formStyle(.grouped)
            .frame(width: 360)
        }
    }
}

@available(macOS 26.0, *)
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
@available(macOS 26.0, *)
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
                Text(L("着色颜色", "Tint color"))
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
                Text(L("明暗", "Brightness")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
@available(macOS 26.0, *)
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

/// 模拟一个文字很多的窗口，用来看玻璃压在杂乱内容上的效果（文字随界面语言变化）
@available(macOS 26.0, *)
private struct DocumentMock: View {
    let dark: Bool

    private var paragraphs: [String] {
        Lang.isChinese ? [
            "液态玻璃会根据背后的内容实时折射和调整明暗，所以同一个效果在不同背景上看起来差别很大。",
            "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.",
            "本周进展：完成设置页设计评审；修复快捷键在全屏 App 下偶发失效的问题；优化图标加载速度。",
            "Q4 roadmap · Growth · Foundation · Enterprise — 12 tickets in review, 3 blocked, 27 done.",
            "下一步计划：补充埋点、整理验收用例、和研发对齐上线时间，周五前给出排期。",
        ] : [
            "Liquid Glass refracts and adapts to whatever is behind it, so the same settings look very different on different backgrounds.",
            "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.",
            "This week: finished the settings design review, fixed the shortcut occasionally failing in full-screen apps, sped up icon loading.",
            "Q4 roadmap · Growth · Foundation · Enterprise — 12 tickets in review, 3 blocked, 27 done.",
            "Next: add analytics events, write acceptance cases, align the launch date with engineering by Friday.",
        ]
    }

    var body: some View {
        let fg: Color = dark ? .white.opacity(0.85) : .black.opacity(0.8)
        let sub: Color = dark ? .white.opacity(0.5) : .black.opacity(0.45)
        let headings = Lang.isChinese ? ["进展", "风险", "数据", "计划"] : ["Progress", "Risks", "Metrics", "Plan"]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 11) }
                Spacer()
                Text(L("周报 - 产品团队", "Weekly Report - Product Team")).font(.system(size: 12, weight: .semibold)).foregroundStyle(sub)
                Spacer()
            }
            Text(L("产品周报", "Weekly Report")).font(.system(size: 26, weight: .bold)).foregroundStyle(fg)
            ForEach(0..<4, id: \.self) { block in
                Text(headings[block]).font(.system(size: 16, weight: .semibold)).foregroundStyle(fg)
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

@available(macOS 26.0, *)
struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section(L("语言", "Language")) {
                Picker(L("界面语言", "Interface language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            }
            Section(L("小圆点", "Floating Dot")) {
                Toggle(L("显示屏幕边缘的小圆点", "Show the dot at the screen edge"), isOn: $settings.dotVisible)
                SliderRow(title: L("不用时的透明度", "Opacity when idle"), value: $settings.dotIdleAlpha, range: 0.15...1) { "\(Int($0 * 100))%" }
            }
            Section(L("快捷键", "Shortcut")) {
                LabeledContent(L("打开 / 收起面板", "Open / close the panel"), value: L("按一下 ⌥⌘", "Tap ⌥⌘"))
                Text(L("按住 ⌥⌘ 时按了别的键或点了鼠标（比如 ⌥⌘D、⌥⌘ 拖动）不会触发。面板里也可以用 ← → 选、回车打开、Esc 关闭。",
                       "Holding ⌥⌘ while pressing another key or clicking (e.g. ⌥⌘D, ⌥⌘-drag) won’t trigger it. In the panel, use ← → to select, Return to open, Esc to close."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("启动", "Startup")) {
                Toggle(L("开机自动启动", "Launch at login"), isOn: Binding(
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
        .onAppear { loginEnabled = SMAppService.mainApp.status == .enabled }
    }
}

// MARK: - 权限

@available(macOS 26.0, *)
struct PermissionsTab: View {
    @ObservedObject private var settings = AppSettings.shared   // 切换语言时刷新
    @State private var axTrusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section(L("辅助功能", "Accessibility")) {
                LabeledContent(L("状态", "Status")) {
                    HStack(spacing: 6) {
                        Image(systemName: axTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(axTrusted ? .green : .orange)
                        Text(axTrusted ? L("已授权", "Granted") : L("未授权，部分功能可能不可用", "Not granted — some features may not work"))
                    }
                }
                PermissionRow(icon: "command",
                              title: L("监听 ⌥⌘ 单按", "Detect the ⌥⌘ tap"),
                              detail: L("只判断 ⌥ 和 ⌘ 是否被单独按下、中间有没有按别的键或点鼠标，不记录、不保存你输入的任何内容。",
                                        "Only checks whether ⌥ and ⌘ were tapped on their own, and whether another key or click happened in between. Nothing you type is recorded or stored."))
                PermissionRow(icon: "rectangle.on.rectangle",
                              title: L("切换到 App 所在的桌面", "Switch to the app’s Space"),
                              detail: L("App 的窗口在另一块屏幕或另一个桌面上时，点图标会把那个窗口带到前面。",
                                        "When an app’s window is on another display or Space, clicking its icon brings that window forward."))
                HStack {
                    Button(L("打开系统设置中的辅助功能…", "Open Accessibility Settings…")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    if !axTrusted {
                        Button(L("重新授权", "Re-authorize")) { reauthorize() }
                    }
                }
                if !axTrusted {
                    Text(L("如果系统设置里 DockDot 的开关已经打开，这里却仍显示未授权，说明那条授权属于旧版本的 DockDot（签名变过）。点「重新授权」会清掉旧授权并弹出系统提示，按提示重新打开开关即可。",
                           "If DockDot’s switch is already on in System Settings but this still says not granted, that entry belongs to an older DockDot build (its signature changed). Click Re-authorize to clear it and get a fresh system prompt, then turn the switch on again."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text(L("授权后状态会自动更新；如果快捷键还没反应，从菜单栏退出 DockDot 再重新打开。没授权时小圆点照常可用。",
                       "The status updates automatically once access is granted. If the shortcut still doesn’t respond, quit DockDot from the menu bar and reopen it. The floating dot works without it."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section(L("不需要的权限", "Not Requested")) {
                PermissionRow(icon: "checkmark.shield",
                              title: L("没有其他权限", "No other permissions"),
                              detail: L("不需要屏幕录制、文件和文件夹、通讯录、麦克风、摄像头等任何其他权限。",
                                        "No Screen Recording, Files & Folders, Contacts, Microphone, Camera or any other permission."))
            }
            Section(L("隐私", "Privacy")) {
                PermissionRow(icon: "wifi.slash",
                              title: L("不联网", "Works offline"),
                              detail: L("DockDot 不连接网络，不收集、不上传任何数据。",
                                        "DockDot never connects to the network and collects or uploads no data."))
                PermissionRow(icon: "internaldrive",
                              title: L("只读本机的 Dock 配置", "Reads only your Dock configuration"),
                              detail: L("读取系统 Dock 的 App 列表和正在运行的 App 来显示面板；所有设置只存在这台 Mac 上。",
                                        "It reads the Dock’s app list and running apps to build the panel. All settings stay on this Mac."))
                PermissionRow(icon: "exclamationmark.circle",
                              title: L("使用了系统非公开接口", "Uses a private system API"),
                              detail: L("跨桌面切换窗口用到了 macOS 的非公开接口（和 AltTab 相同）。以后系统更新可能让它失效，那时会退回普通的打开方式。",
                                        "Switching to windows on other Spaces uses a private macOS API (the same one AltTab uses). A future macOS update may break it; DockDot then falls back to a normal app activation."))
            }
        }
        .formStyle(.grouped)
        .onAppear { axTrusted = AXIsProcessTrusted() }
        // 在系统设置里打开开关后，这里每 2 秒自动刷新一次状态
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            axTrusted = AXIsProcessTrusted()
        }
    }

    /// 清掉这个 App 的旧授权记录（只影响 DockDot 自己），再弹出系统的授权提示
    private func reauthorize() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "local.dockdot"]
        try? p.run()
        p.waitUntilExit()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

@available(macOS 26.0, *)
private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 关于

@available(macOS 26.0, *)
struct AboutTab: View {
    @ObservedObject private var settings = AppSettings.shared   // 切换语言时刷新
    private static let repo = "https://github.com/mars7233/DockDot"

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 112, height: 112)
            VStack(spacing: 4) {
                Text("DockDot").font(.system(size: 28, weight: .bold))
                Text(L("版本 \(version)", "Version \(version)")).foregroundStyle(.secondary)
            }
            Text(L("把 Mac 的 Dock 收进一个小圆点。", "Your Mac’s Dock, tucked into a small dot."))
                .font(.title3)

            HStack(spacing: 12) {
                Link(destination: URL(string: Self.repo)!) {
                    Label { Text(L("在 GitHub 上查看", "View on GitHub")) } icon: { GitHubMark().frame(width: 16, height: 16) }
                }
                .buttonStyle(.borderedProminent)
                Link(L("反馈问题", "Report an Issue"), destination: URL(string: Self.repo + "/issues")!)
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)

            VStack(spacing: 6) {
                Text("© 2026 Mason").font(.callout)
                HStack(spacing: 4) {
                    Text(L("许可证：", "License:"))
                    Link("PolyForm Strict 1.0.0", destination: URL(string: Self.repo + "/blob/main/LICENSE")!)
                }
                .font(.callout)
                Text(L("仅限个人或非营利使用；修改、复制、转发或商业使用需获得作者许可。",
                       "Personal and noncommercial use only. Modifying, copying, redistributing or commercial use requires the author’s permission."))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: 520)

            VStack(spacing: 4) {
                Text(L("致谢", "Thanks")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Link("dok", destination: URL(string: "https://github.com/chillintheshade/dok")!)
                    Link("AltTab", destination: URL(string: "https://github.com/lwouis/alt-tab-macos")!)
                    Link("RadialMenu", destination: URL(string: "https://github.com/ricky-yosh/RadialMenu")!)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// GitHub 标志（Octicons mark-github），用模板图跟随按钮文字颜色
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
