//
//  AutoScrollUtils.swift
//  Mos
//  自动滚动工具方法
//  Created by Auto-Scroll Implementation on 2025/11/29.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class AutoScrollUtils {

    // 单例
    static let shared = AutoScrollUtils()
    init() { NSLog("Module initialized: AutoScrollUtils") }

    /// 计算两点之间的距离
    static func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point2.x - point1.x
        let dy = point2.y - point1.y
        return sqrt(dx * dx + dy * dy)
    }

    /// 检查应用是否在例外列表中
    func isAppInExceptionList(_ bundleIdentifier: String) -> Bool {
        let exceptionList = Options.shared.autoScroll.appExceptions
        return exceptionList.contains(bundleIdentifier)
    }

    /// 获取当前活动应用的 Bundle Identifier
    func getCurrentAppBundleIdentifier() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// 检查当前应用是否应该禁用自动滚动
    func shouldDisableAutoScrollForCurrentApp() -> Bool {
        guard let bundleId = getCurrentAppBundleIdentifier() else {
            return false
        }
        return isAppInExceptionList(bundleId)
    }

    /// 获取应用特定的拖动阈值
    func getDragThreshold(for bundleIdentifier: String) -> CGFloat? {
        // TODO: 实现应用特定设置
        return nil
    }

    /// 格式化灵敏度值用于显示
    static func formatSensitivity(_ value: Double) -> String {
        return String(format: "%.1fx", value)
    }

    /// 验证设置值是否在有效范围内
    static func validateSensitivity(_ value: Double) -> Double {
        return max(0.2, min(3.0, value))
    }

    static func validateDeadZone(_ value: CGFloat) -> CGFloat {
        return max(0.0, min(20.0, value))
    }

    static func validateDragThreshold(_ value: CGFloat) -> CGFloat {
        return max(5.0, min(30.0, value))
    }

    static func validateMaxSpeed(_ value: CGFloat) -> CGFloat {
        return max(10.0, min(100.0, value))
    }
}
