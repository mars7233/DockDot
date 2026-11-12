import AppKit

/// 让 NSGlassEffectView 渲染出和系统程序坞几乎一样的液态玻璃。
///
/// 实测（和真实 Dock 放在同一块背景上逐像素对比）需要三样东西，缺一不可：
/// 1. 私有材质档位 `_variant = 3`（dock）：底板颜色、取背景色的 1px 边、左侧暗色厚度线都来自它。
///    公开的 `.regular` 会额外叠一层白（实测在壁纸上比 Dock 亮约 93），完全不是一回事。
/// 2. 窗口按「激活」状态渲染：AppKit 只在玻璃进入窗口时取一次窗口的激活状态，
///    不会成为 key 的面板会一直是乳白的「非激活」材质（模糊 5.5、不加饱和）。
///    窗口要回答 `_hasActiveAppearance` 等为真，再调一次 `_windowChangedKeyState` 让玻璃重新取样。
/// 3. Dock 的内折射参数（高度 13.28、强度 -29.88）：文字背景上和 Dock 的差距从 26 降到 10。
/// 都是私有接口，系统没有时自动跳过，退回普通玻璃。参考 tungsten-edge / Dockline 的逆向结果。
@available(macOS 26.0, *)
enum DockGlass {
    static let dockVariant = 3
    static let refractionHeight = 13.28
    static let refractionAmount = -29.88

    static var isSupported: Bool {
        NSGlassEffectView.instancesRespond(to: NSSelectorFromString("set_variant:"))
    }

    /// 设成程序坞材质；不支持时返回 false
    @discardableResult
    static func applyDockMaterial(_ glass: NSGlassEffectView) -> Bool {
        guard isSupported else { return false }
        glass.setValue(dockVariant, forKey: "_variant")
        return true
    }

    /// 让玻璃按窗口当前（被我们强制为激活的）状态重新取样
    static func refreshActiveState(_ glass: NSGlassEffectView) {
        let sel = NSSelectorFromString("_windowChangedKeyState")
        if glass.responds(to: sel) { _ = glass.perform(sel) }
    }

    /// 把玻璃滤镜的内折射改成 Dock 的值（滤镜归系统所有，只能复制一份改了再换回去）
    static func applyDockRefraction(_ layer: CALayer) {
        if var filters = layer.filters as? [NSObject] {
            var changed = false
            for (i, f) in filters.enumerated() {
                guard (f.value(forKey: "type") as? String) == "glassBackground",
                      let keys = f.value(forKey: "inputKeys") as? [String],
                      keys.contains("inputInnerRefractionHeight"), keys.contains("inputInnerRefractionAmount"),
                      let copy = f.copy() as? NSObject else { continue }
                if (f.value(forKey: "inputInnerRefractionHeight") as? NSNumber)?.doubleValue == refractionHeight { continue }
                copy.setValue(refractionHeight, forKey: "inputInnerRefractionHeight")
                copy.setValue(refractionAmount, forKey: "inputInnerRefractionAmount")
                filters[i] = copy
                changed = true
            }
            if changed {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.filters = filters
                CATransaction.commit()
            }
        }
        layer.sublayers?.forEach(applyDockRefraction)
    }

    /// 玻璃上屏之后做的两步：重新取样激活状态，再改折射（改材质或尺寸后系统会换掉滤镜，所以每次显示都做）
    static func finish(_ glasses: [NSGlassEffectView]) {
        DispatchQueue.main.async {
            glasses.forEach(refreshActiveState)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                for g in glasses { if let l = g.layer { applyDockRefraction(l) } }
            }
        }
    }
}
