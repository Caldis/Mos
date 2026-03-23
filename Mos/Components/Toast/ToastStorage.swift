//
//  ToastStorage.swift
//  Mos
//  Toast 组件独立持久化 - 使用独立 UserDefaults suite
//

import Cocoa

/// Toast 组件的独立持久化存储
///
/// 使用独立的 UserDefaults suite (基于 Bundle ID)，不与宿主应用的 UserDefaults 混合。
/// 这确保 Toast 模块可作为独立组件在任何 macOS 应用中复用。
class ToastStorage {

    static let shared = ToastStorage()

    private let defaults: UserDefaults

    private enum Keys {
        static let positionX = "positionX"
        static let positionY = "positionY"
        static let maxCount = "maxCount"
        static let showsAccentIndicator = "showsAccentIndicator"
    }

    init() {
        let suiteName = "\(Bundle.main.bundleIdentifier ?? "app").toast"
        defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults.standard
    }

    // MARK: - Position

    /// 保存的锚点位置 (绝对屏幕坐标)。nil 表示使用默认位置。
    var savedPosition: NSPoint? {
        get {
            guard defaults.object(forKey: Keys.positionX) != nil,
                  defaults.object(forKey: Keys.positionY) != nil else {
                return nil
            }
            let point = NSPoint(
                x: CGFloat(defaults.double(forKey: Keys.positionX)),
                y: CGFloat(defaults.double(forKey: Keys.positionY))
            )
            // 坐标有效性校验：检查锚点是否仍在任何屏幕可见区域内
            for screen in NSScreen.screens {
                if screen.visibleFrame.contains(point) {
                    return point
                }
            }
            // 不在任何屏幕上 (如外接显示器已断开)，回退到默认
            return nil
        }
        set {
            if let point = newValue {
                defaults.set(Double(point.x), forKey: Keys.positionX)
                defaults.set(Double(point.y), forKey: Keys.positionY)
            } else {
                defaults.removeObject(forKey: Keys.positionX)
                defaults.removeObject(forKey: Keys.positionY)
            }
        }
    }

    /// 是否有保存的自定义位置
    var hasCustomPosition: Bool {
        return savedPosition != nil
    }

    // MARK: - Max Count

    /// 最大同时显示数 (1-8，默认 4)
    var maxCount: Int {
        get {
            let val = defaults.integer(forKey: Keys.maxCount)
            return val > 0 ? min(max(val, 1), 8) : 4
        }
        set {
            defaults.set(min(max(newValue, 1), 8), forKey: Keys.maxCount)
        }
    }

    // MARK: - Accent Indicator

    /// 是否显示 toast 左侧 ribbon / 竖条，默认开启。
    ///
    /// 调试面板可以直接读写这个值，再由 toast 渲染层决定是否展示强调条。
    var showsAccentIndicator: Bool {
        get {
            guard defaults.object(forKey: Keys.showsAccentIndicator) != nil else {
                return true
            }
            return defaults.bool(forKey: Keys.showsAccentIndicator)
        }
        set {
            defaults.set(newValue, forKey: Keys.showsAccentIndicator)
        }
    }

    // MARK: - Reset

    /// 重置位置到默认
    func resetPosition() {
        savedPosition = nil
    }
}
