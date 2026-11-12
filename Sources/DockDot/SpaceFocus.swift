import AppKit
import ApplicationServices

// 取 AX 窗口对应的 CGWindowID（私有但稳定，AltTab 等工具都在用）
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

/// 切到 App 在「其他桌面（Space）」上的窗口。
///
/// 辅助功能接口只能看到当前正在显示的桌面上的窗口；App 的窗口如果在另一块屏幕的
/// 另一个桌面上，普通的「激活 App」不会把那块屏幕切过去。这里参考 AltTab：
/// 从系统窗口列表（包含所有桌面）里找到这个 App 最前面的窗口，再通过 SkyLight
/// 让窗口服务器把这个窗口放到最前，系统会自动切到它所在的桌面。
@available(macOS 26.0, *)
enum SpaceFocus {
    private typealias SetFrontFn = @convention(c) (UnsafeMutableRawPointer, CGWindowID, UInt32) -> Int32
    private typealias PostEventFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> Int32

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let setFront: SetFrontFn? = symbol("_SLPSSetFrontProcessWithOptions")
    private static let postEvent: PostEventFn? = symbol("SLPSPostEventRecordTo")
    // GetProcessForPID 在 Swift 里被标为不可用，但系统里仍然存在，动态取
    private typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus
    private static let getPSN: GetPSNFn? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID") else { return nil }  // RTLD_DEFAULT
        return unsafeBitCast(p, to: GetPSNFn.self)
    }()

    private static func symbol<T>(_ name: String) -> T? {
        guard let h = skyLight, let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    enum Decision: CustomStringConvertible {
        case normal(String)              // 当前桌面就有窗口 / 没找到别处的窗口：正常激活
        case otherSpace(CGWindowID)      // 窗口在其他桌面：切过去

        var description: String {
            switch self {
            case let .normal(why): "正常激活（\(why)）"
            case let .otherSpace(w): "切到其他桌面上的窗口 #\(w)"
            }
        }
    }

    static func decide(for app: NSRunningApplication) -> Decision {
        let pid = app.processIdentifier
        var axIDs = Set<CGWindowID>()
        var visibleHere = false
        var value: CFTypeRef?
        let axApp = AXUIElementCreateApplication(pid)
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
           let wins = value as? [AXUIElement] {
            for w in wins {
                var id: CGWindowID = 0
                if _AXUIElementGetWindow(w, &id) == .success { axIDs.insert(id) }
                var m: CFTypeRef?
                let minimized = AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &m) == .success
                    && (m as? Bool) == true
                if !minimized { visibleHere = true }
            }
        }
        if visibleHere { return .normal("当前显示的桌面上有窗口") }

        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return .normal("读不到窗口列表") }
        // 窗口列表从前到后排列：第一个属于这个 App、又不在当前桌面上的普通窗口，就是它最近用的窗口
        let hit = list.first { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID, !axIDs.contains(id),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) >= 120, (b["Height"] ?? 0) >= 80 else { return false }
            return true
        }
        guard let id = hit?[kCGWindowNumber as String] as? CGWindowID else { return .normal("其他桌面上也没有窗口") }
        return .otherSpace(id)
    }

    /// 返回 true 表示已切到其他桌面上的窗口；false 时调用方照常激活 App
    static func focusIfOnOtherSpace(_ app: NSRunningApplication) -> Bool {
        guard case let .otherSpace(wid) = decide(for: app), let setFront, let postEvent, let getPSN else { return false }
        var psn = ProcessSerialNumber()
        guard withUnsafeMutablePointer(to: &psn, { getPSN(app.processIdentifier, $0) }) == noErr else { return false }
        withUnsafeMutablePointer(to: &psn) { p in
            _ = setFront(p, wid, 0x200)   // kCPSUserGenerated
            // 让这个窗口成为 key window（和 AltTab 一样发两条事件记录）
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x3a] = 0x10
            withUnsafeBytes(of: wid) { for i in 0..<4 { bytes[0x3c + i] = $0[i] } }
            for i in 0x20..<0x30 { bytes[i] = 0xff }
            bytes[0x08] = 0x01
            _ = postEvent(p, &bytes)
            bytes[0x08] = 0x02
            _ = postEvent(p, &bytes)
        }
        return true
    }
}
