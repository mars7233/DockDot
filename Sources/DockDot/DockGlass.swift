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

    /// 用私有的 `_setPath:` 给玻璃设任意形状（视图坐标，y 向上）；nil 恢复成普通圆角矩形
    @discardableResult
    static func setShape(_ glass: NSGlassEffectView, _ path: CGPath?) -> Bool {
        let sel = NSSelectorFromString("_setPath:")
        guard glass.responds(to: sel), let imp = glass.method(for: sel) else { return false }
        typealias SetPath = @convention(c) (AnyObject, Selector, CGPath?) -> Void
        unsafeBitCast(imp, to: SetPath.self)(glass, sel, path)
        return true
    }

    /// 圆环路径：内圈反方向绘制，非零填充规则下中间被挖空
    static func ringPath(center c: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.addArc(center: c, radius: outer, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        p.closeSubpath()
        p.move(to: CGPoint(x: c.x + inner, y: c.y))
        p.addArc(center: c, radius: inner, startAngle: 0, endAngle: -2 * .pi, clockwise: true)
        p.closeSubpath()
        return p
    }

    /// 让玻璃按窗口当前（被我们强制为激活的）状态重新取样
    static func refreshActiveState(_ glass: NSGlassEffectView) {
        let sel = NSSelectorFromString("_windowChangedKeyState")
        if glass.responds(to: sel) { _ = glass.perform(sel) }
    }

    /// 玻璃滤镜参数。「扭曲程度」0…1 同时决定内折射的高度和强度：
    /// 约 0.05 ≈ 系统 Dock 底板（13.28 / -29.88），0.5 = 高度 40 / 强度 -120（设置里方案 4 的扭曲）
    typealias Tuning = [String: Double]

    static func tuning(distortion d: Double, strongHighlight: Bool = false) -> Tuning {
        let d = min(max(d, 0), 1)
        var t: Tuning = ["inputInnerRefractionHeight": 10 + 60 * d,
                         "inputInnerRefractionAmount": -(20 + 200 * d)]
        if strongHighlight {                 // 圆心玻璃：加强边缘高光
            t["inputKeyFillHighlightAmount"] = 1.0
            t["inputKeyFillHighlightHeight"] = 2
            // 高光默认只在上下各约 120° 的弧上，其余地方露出边缘那条暗线，看起来像一圈没闭合的边框；
            // 铺满整圈后边缘是一条连续闭合的亮边
            t["inputKeyFillHighlightSpread"] = Double.pi
            t["inputKeyFillHighlightSpreadSDR"] = Double.pi
        }
        return t
    }

    /// 把参数写进玻璃滤镜（滤镜归系统所有，只能复制一份改了再换回去）
    static func apply(_ tuning: Tuning, to layer: CALayer) {
        if var filters = layer.filters as? [NSObject], !tuning.isEmpty {
            var changed = false
            for (i, f) in filters.enumerated() {
                guard (f.value(forKey: "type") as? String) == "glassBackground",
                      let keys = f.value(forKey: "inputKeys") as? [String],
                      let copy = f.copy() as? NSObject else { continue }
                var differs = false
                for (k, v) in tuning where keys.contains(k) {
                    if (f.value(forKey: k) as? NSNumber)?.doubleValue != v { copy.setValue(v, forKey: k); differs = true }
                }
                if differs { filters[i] = copy; changed = true }
            }
            if changed {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.filters = filters
                CATransaction.commit()
            }
        }
        layer.sublayers?.forEach { apply(tuning, to: $0) }
    }

    /// 玻璃上屏之后做的两步：重新取样激活状态，再写入各自的参数（改材质或尺寸后系统会换掉滤镜，所以每次显示都做）
    static func finish(_ items: [(NSGlassEffectView, Tuning)]) {
        DispatchQueue.main.async {
            items.forEach { refreshActiveState($0.0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                for (g, t) in items { if let l = g.layer { apply(t, to: l) } }
            }
        }
    }
}
