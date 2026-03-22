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
            // 坐标有效性校验：检查是否在任何可见屏幕范围内
            for screen in NSScreen.screens {
                if screen.frame.contains(point) {
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

    // MARK: - Reset

    /// 重置位置到默认
    func resetPosition() {
        savedPosition = nil
    }
}
