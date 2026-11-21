//
//  StatusItemSecondaryClickAction.swift
//  Mos
//  状态栏图标的次要点击 (右键) 行为
//

import Foundation

/// 状态栏图标被次要点击时执行的行为.
///
/// raw value 会写入 UserDefaults, 不要重命名.
enum StatusItemSecondaryClickAction: String, CaseIterable {
    /// 和主要点击一致, 弹出状态栏菜单 (默认值, 保持旧版本行为)
    case menu
    /// 开关全局平滑滚动
    case toggleSmooth
    /// 开关全局滚动方向翻转
    case toggleReverse
    /// 直接打开偏好设置
    case preferences

    static let `default` = StatusItemSecondaryClickAction.menu

    /// 从持久化值还原. 缺失或无法识别的值 (例如从更新的 Mos 降级回来) 回落到默认行为
    init(storedValue: String?) {
        self = storedValue.flatMap(StatusItemSecondaryClickAction.init(rawValue:)) ?? .default
    }

    /// 该行为所开关的滚动选项; 不开关任何选项时为 nil
    var toggledScrollOption: ScrollToggleOption? {
        switch self {
        case .toggleSmooth: return .smooth
        case .toggleReverse: return .reverse
        case .menu, .preferences: return nil
        }
    }

    /// 偏好设置下拉框中的标题
    var localizedTitle: String {
        switch self {
        case .menu:
            return NSLocalizedString("Show Menu", comment: "Status bar icon right click action: pop up the status bar menu")
        case .toggleSmooth:
            return NSLocalizedString("Toggle Smooth Scrolling", comment: "Status bar icon right click action: turn smooth scrolling on or off")
        case .toggleReverse:
            return NSLocalizedString("Toggle Reverse Scrolling", comment: "Status bar icon right click action: turn scroll direction reversing on or off")
        case .preferences:
            return NSLocalizedString("Open Preferences", comment: "Status bar icon right click action: open the preferences window")
        }
    }
}

/// 可以被状态栏图标直接开关的全局滚动选项
enum ScrollToggleOption {
    case smooth
    case reverse

    func isEnabled(in options: OPTIONS_SCROLL_DEFAULT) -> Bool {
        switch self {
        case .smooth: return options.smooth
        case .reverse: return options.reverse
        }
    }

    func setEnabled(_ enabled: Bool, in options: OPTIONS_SCROLL_DEFAULT) {
        switch self {
        case .smooth: options.smooth = enabled
        case .reverse: options.reverse = enabled
        }
    }
}

/// 状态栏图标一次点击应产生的结果
enum StatusItemClickOutcome: Equatable {
    case showMenu
    case openPreferences
    case toggleScroll(ScrollToggleOption)
}

/**
 * 点击路由与图标状态 (纯函数, 与 AppKit 解耦以便测试)
 **/
extension StatusItemSecondaryClickAction {
    /// 决定一次点击的结果.
    ///
    /// 主要点击永远弹出菜单; 没有辅助功能权限时同样只弹菜单, 否则快捷开关会静默改掉一个
    /// 当前并不生效的设置, 而请求授权的入口也就没地方点了.
    static func outcome(
        isSecondaryClick: Bool,
        action: StatusItemSecondaryClickAction,
        isAccessibilityTrusted: Bool
    ) -> StatusItemClickOutcome {
        guard isSecondaryClick, isAccessibilityTrusted else { return .showMenu }
        switch action {
        case .menu: return .showMenu
        case .preferences: return .openPreferences
        case .toggleSmooth: return .toggleScroll(.smooth)
        case .toggleReverse: return .toggleScroll(.reverse)
        }
    }

    /// 图标是否变暗: 次要点击被配置成快捷开关, 且该开关当前处于关闭状态.
    /// 让用户不用打开菜单就能看出开关状态.
    static func iconAppearsDisabled(
        action: StatusItemSecondaryClickAction,
        isSmoothEnabled: Bool,
        isReverseEnabled: Bool
    ) -> Bool {
        switch action.toggledScrollOption {
        case .smooth: return !isSmoothEnabled
        case .reverse: return !isReverseEnabled
        case nil: return false
        }
    }
}
