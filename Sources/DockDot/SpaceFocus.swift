import AppKit
import ApplicationServices

// 取 AX 窗口对应的 CGWindowID（私有但稳定，AltTab 等工具都在用）
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

// 用「远程令牌」直接构造某个 App 的辅助功能元素：这样连其他桌面上的窗口也能拿到（AltTab 同款做法）
@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

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

    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let mainConnection: MainConnFn? = symbol("SLSMainConnectionID")
    private static let spacesForWindows: SpacesForWindowsFn? = symbol("SLSCopySpacesForWindows")

    private typealias CopyManagedFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let copyManagedDisplaySpaces: CopyManagedFn? = symbol("SLSCopyManagedDisplaySpaces")

    /// 每块屏幕：标识、当前桌面、按顺序排列的所有桌面
    private static func managedDisplays() -> [(uuid: String, current: Int, spaces: [Int])] {
        guard let mainConnection, let copyManagedDisplaySpaces,
              let arr = copyManagedDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let uuid = d["Display Identifier"] as? String,
                  let cur = (d["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int else { return nil }
            let spaces = (d["Spaces"] as? [[String: Any]] ?? []).compactMap { $0["ManagedSpaceID"] as? Int }
            return (uuid, cur, spaces)
        }
    }

    /// 屏幕标识对应的显示器（"Main" 表示主屏）
    private static func displayID(for uuid: String) -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &n) == .success else { return nil }
        for id in ids.prefix(Int(n)) {
            if uuid == "Main", CGDisplayIsMain(id) != 0 { return id }
            if let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
               let str = CFUUIDCreateString(nil, u) as String?, str.caseInsensitiveCompare(uuid) == .orderedSame { return id }
        }
        return nil
    }

    /// 后备方案：用系统的「向左/向右移动一个桌面」快捷键（Ctrl+← / Ctrl+→）把目标屏幕切到指定桌面。
    /// 这个快捷键作用于鼠标所在的屏幕，所以先把鼠标临时移到目标屏幕，切完再移回来。
    private static func switchDisplay(toSpace target: Int, then done: @escaping () -> Void) {
        guard let d = managedDisplays().first(where: { $0.spaces.contains(target) }),
              d.current != target,
              let from = d.spaces.firstIndex(of: d.current), let to = d.spaces.firstIndex(of: target),
              let display = displayID(for: d.uuid) else { done(); return }
        let steps = to - from
        debugLog?("keyboard fallback: display \(d.uuid) \(d.current) -> \(target), steps \(steps)")
        let original = CGEvent(source: nil)?.location ?? .zero
        let b = CGDisplayBounds(display)
        CGWarpMouseCursorPosition(CGPoint(x: b.midX, y: b.midY))
        let key: CGKeyCode = steps > 0 ? 124 : 123            // → / ←
        let flags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        for i in 0..<abs(steps) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 + Double(i) * 0.08) {
                for down in [true, false] {
                    let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
                    e?.flags = flags
                    e?.post(tap: .cghidEventTap)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(abs(steps)) * 0.08) {
            CGWarpMouseCursorPosition(original)
            done()
        }
    }

    /// 窗口所在的桌面编号；空数组表示它不在任何桌面上（隐藏/关掉但没销毁的窗口）
    private static func spaces(of wid: CGWindowID) -> [Int]? {
        guard let mainConnection, let spacesForWindows else { return nil }
        return spacesForWindows(mainConnection(), 7, [Int(wid)] as CFArray)?.takeRetainedValue() as? [Int]
    }

    /// 找到 pid 这个 App 里窗口号为 wid 的辅助功能元素（包括在其他桌面上的窗口）
    private static func axWindow(pid: pid_t, wid: CGWindowID) -> AXUIElement? {
        var token = Data(count: 20)
        withUnsafeBytes(of: pid) { token.replaceSubrange(0..<4, with: $0) }
        token.replaceSubrange(4..<8, with: [0, 0, 0, 0])
        withUnsafeBytes(of: Int32(0x636f636f)) { token.replaceSubrange(8..<12, with: $0) }   // "coco"
        for elementID in UInt64(0)..<2000 {
            withUnsafeBytes(of: elementID) { token.replaceSubrange(12..<20, with: $0) }
            guard let el = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            var w: CGWindowID = 0
            if _AXUIElementGetWindow(el, &w) == .success, w == wid { return el }
        }
        return nil
    }

    /// 调试用：--open-app 会设置它，把每一步写进日志
    static var debugLog: ((String) -> Void)?

    private static func symbol<T>(_ name: String) -> T? {
        guard let h = skyLight, let p = dlsym(h, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    enum Decision: CustomStringConvertible {
        case normal(String)              // 当前桌面就有窗口 / 没找到别处的窗口：正常激活
        case otherSpace(CGWindowID)      // 窗口在其他桌面：切过去

        var description: String {
            switch self {
            case let .normal(why): L("正常激活（\(why)）", "Normal activation (\(why))")
            case let .otherSpace(w): L("切到其他桌面上的窗口 #\(w)", "Switch to window #\(w) on another Space")
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
                // 只有「正常的文档窗口」才算当前桌面上有窗口；悬浮的小窗（画中画、置顶小播放器等）不算，
                // 否则这类窗口会挡住跨桌面切换
                var sr: CFTypeRef?
                let subrole = AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &sr) == .success ? sr as? String : nil
                var sz: CFTypeRef?
                var size = CGSize.zero
                if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sz) == .success, let v = sz {
                    AXValueGetValue(v as! AXValue, .cgSize, &size)
                }
                if !minimized, subrole == (kAXStandardWindowSubrole as String), size.width >= 120, size.height >= 80 {
                    visibleHere = true
                }
            }
        }
        if visibleHere { return .normal(L("当前显示的桌面上有窗口", "has a window on a visible Space")) }

        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return .normal(L("读不到窗口列表", "window list unavailable")) }
        // 窗口列表从前到后排列：第一个属于这个 App、又不在当前桌面上的普通窗口，就是它最近用的窗口
        let hit = list.first { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  // 普通窗口是第 0 层；「置顶」的窗口（比如视频播放器的置顶模式）在第 3 层。
                  // 菜单、弹出框、状态栏这些在更高的层，不算
                  let layer = w[kCGWindowLayer as String] as? Int, (0...8).contains(layer),
                  let id = w[kCGWindowNumber as String] as? CGWindowID, !axIDs.contains(id),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  (b["Width"] ?? 0) >= 120, (b["Height"] ?? 0) >= 80 else { return false }
            // 不在任何桌面上的窗口（隐藏或关掉但没销毁的）不算
            if let sp = spaces(of: id), sp.isEmpty { return false }
            return true
        }
        guard let id = hit?[kCGWindowNumber as String] as? CGWindowID else { return .normal(L("其他桌面上也没有窗口", "no window on other Spaces either")) }
        return .otherSpace(id)
    }

    /// 返回 true 表示已切到其他桌面上的窗口；false 时调用方照常激活 App
    static func focusIfOnOtherSpace(_ app: NSRunningApplication) -> Bool {
        let decision = decide(for: app)
        debugLog?("decision: \(decision); symbols setFront=\(setFront != nil) postEvent=\(postEvent != nil) getPSN=\(getPSN != nil)")
        guard case let .otherSpace(wid) = decision, let setFront, let postEvent, let getPSN else { return false }
        var psn = ProcessSerialNumber()
        let psnErr = withUnsafeMutablePointer(to: &psn, { getPSN(app.processIdentifier, $0) })
        debugLog?("GetProcessForPID -> \(psnErr)")
        guard psnErr == noErr else { return false }
        bringForward(psn: psn, wid: wid, pid: app.processIdentifier, setFront: setFront, postEvent: postEvent)
        // 有的窗口（比如 PiliPlus 的置顶播放窗口）上面这几步不会让系统切桌面：稍等一下检查，没切过去就用快捷键切
        if let target = spaces(of: wid)?.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {   // 等切桌面动画结束再检查，避免多切一格
                let shown = managedDisplays().contains { $0.current == target }
                debugLog?("after bringForward: target space \(target) showing=\(shown)")
                guard !shown else { return }
                switchDisplay(toSpace: target) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        bringForward(psn: psn, wid: wid, pid: app.processIdentifier, setFront: setFront, postEvent: postEvent)
                        debugLog?("after keyboard fallback: showing=\(managedDisplays().contains { $0.current == target })")
                    }
                }
            }
        }
        return true
    }

    private static func bringForward(psn: ProcessSerialNumber, wid: CGWindowID, pid: pid_t,
                                     setFront: SetFrontFn, postEvent: PostEventFn) {
        var psn = psn
        withUnsafeMutablePointer(to: &psn) { p in
            let r = setFront(p, wid, 0x200)   // kCPSUserGenerated
            debugLog?("SLPSSetFrontProcessWithOptions(#\(wid)) -> \(r)")
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
        // 再对这个窗口执行「提到最前」：对大多数 App，这一步会让 macOS 切到它所在的桌面
        if let el = axWindow(pid: pid, wid: wid) {
            let r = AXUIElementPerformAction(el, kAXRaiseAction as CFString)
            debugLog?("AXRaise -> \(r.rawValue)")
        } else {
            debugLog?("AX element for #\(wid) not found")
        }
    }
}
