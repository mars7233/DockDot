import AppKit

struct DockItem {
    let url: URL
    let name: String
    let icon: NSImage
    let isRunning: Bool
    let isPinned: Bool
}

/// 读取系统 Dock 的固定 App（com.apple.dock / persistent-apps）和正在运行的 App。
enum DockReader {
    private static let domain = "com.apple.dock" as CFString

    static func pinnedURLs() -> [URL] {
        CFPreferencesAppSynchronize(domain)
        guard let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] else {
            return []
        }
        return tiles.compactMap { tile in
            guard let td = tile["tile-data"] as? [String: Any],
                  let fd = td["file-data"] as? [String: Any],
                  let s = fd["_CFURLString"] as? String else { return nil }
            // _CFURLStringType 15 = file:// URL，0 = POSIX 路径
            if (fd["_CFURLStringType"] as? Int ?? 15) == 15 { return URL(string: s) }
            return URL(fileURLWithPath: s)
        }
    }

    static func key(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func items() -> (pinned: [DockItem], running: [DockItem]) {
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let runningKeys = Set(runningApps.compactMap { $0.bundleURL.map(key) })

        var urls = pinnedURLs()
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        if !urls.contains(where: { key($0) == key(finder) }) { urls.insert(finder, at: 0) }

        let fm = FileManager.default
        let pinned = urls.filter { fm.fileExists(atPath: $0.path) }.map { u in
            DockItem(url: u,
                     name: fm.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: ""),
                     icon: NSWorkspace.shared.icon(forFile: u.path),
                     isRunning: runningKeys.contains(key(u)),
                     isPinned: true)
        }

        let pinnedKeys = Set(urls.map(key))
        let others = runningApps.compactMap { a -> DockItem? in
            guard let u = a.bundleURL, !pinnedKeys.contains(key(u)) else { return nil }
            return DockItem(url: u,
                            name: a.localizedName ?? u.deletingPathExtension().lastPathComponent,
                            icon: a.icon ?? NSWorkspace.shared.icon(forFile: u.path),
                            isRunning: true,
                            isPinned: false)
        }
        return (pinned, others)
    }

    /// 和点 Dock 图标一样：没开就启动，开着就切过去（最小化的窗口也会恢复）
    static func open(_ item: DockItem) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: item.url, configuration: cfg) { _, err in
            if let err { NSLog("DockDot: 打开 \(item.name) 失败: \(err)") }
        }
    }
}
