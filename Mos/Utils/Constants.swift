//
//  Constants.swift
//  Mos
//  常量
//  Created by Caldis on 2019/3/4.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

// 动画
struct ANIMATION {
    static let duration = 0.3
}

// 窗口
struct WINDOW_IDENTIFIER {
    static let introductionWindowController = "introductionWindowController"
    static let welcomeWindowController = "welcomeWindowController"
    static let monitorWindowController = "monitorWindowController"
    static let preferencesWindowController = "preferencesWindowController"
}
struct VIEW_IDENTIFIER {
    static let introductionStepOneViewController = "introductionStepOneViewController"
    static let introductionStepTwoViewController = "introductionStepTwoViewController"
    static let introductionStepThreeViewController = "introductionStepThreeViewController"
}

// 视图
struct PANEL_IDENTIFIER {
    static let general = "general"
    static let scrolling = "scrolling"
    static let scrollingWithApplication = "scrollingWithApplication"
    static let buttons = "buttons"
    static let application = "application"
    static let list = [general, scrolling, buttons, application]
}
let PANEL_PADDING = CGFloat(42.0) // 顶部导航栏高度
let TOOLBAR_HEIGHT = CGFloat(80.0) // 偏好的 Toolbar 高度
// macOS 版本补偿高度 - 只在特定版本生效
var MACOS_TAHOE_COMPENSATE: CGFloat {
    if #available(macOS 26.0, *) {
        return CGFloat(8) // 26 版本的额外高度, 否则底部会被吃掉一部分
    } else {
        return CGFloat(0) // 其他版本不需要补偿
    }
}

// 气泡弹窗
struct POPOVER_IDENTIFIER {
    static let statusItemPopoverViewController = "statusItemPopoverViewController"
    static let statusItemMainPanelViewController = "statusItemMainPanelViewController"
}

// 事件处理应用
struct SPECIAL_EVENT_SOURCE_APPLICATION {
    static let logitechOptions = "com.logitech.manager.daemon"
}

enum ScrollDurationLimits {
    static let simulateTrackpadDefault: Double = 4.75
}

/// 默认设置项
// 常规
class OPTIONS_GENERAL_DEFAULT {
    // 自启
    var autoLaunch = false {
        willSet {Utils.launchAtStartup(on: newValue)}
        didSet {Options.shared.saveOptions()}
    }
    // 隐藏
    var hideStatusItem = false {
        willSet {newValue ? StatusItemManager.hideStatusItem() : StatusItemManager.showStatusItem()}
        didSet {Options.shared.saveOptions()}
    }
}

// 按键
class OPTIONS_BUTTONS_DEFAULT: Codable {
    var binding:[ButtonBinding] = [] {
        didSet { Options.shared.saveOptions() }
    }
}

// 滚动
class OPTIONS_SCROLL_DEFAULT: Codable {
    var smooth = true {
        didSet {Options.shared.saveOptions()}
    }
    var reverse = true {
        didSet {Options.shared.saveOptions()}
    }
    var reverseVertical = true {
        didSet {Options.shared.saveOptions()}
    }
    var reverseHorizontal = true {
        didSet {Options.shared.saveOptions()}
    }
    var dash:Int? = 0 {
        didSet {Options.shared.saveOptions()}
    }
    var toggle:Int? = 56 {
        didSet {Options.shared.saveOptions()}
    }
    var block:Int? = 55 {
        didSet {Options.shared.saveOptions()}
    }
    var step = 33.6 {
        didSet {Options.shared.saveOptions()}
    }
    var speed = 2.70 {
        didSet {Options.shared.saveOptions()}
    }
    var duration = 4.35 {
        didSet {Options.shared.saveOptions()}
    }
    var durationTransition: Double {
        OPTIONS_SCROLL_DEFAULT.generateDurationTransition(with: duration)
    }
    var deadZone = 1.00 {
        didSet {Options.shared.saveOptions()}
    }
    var smoothSimTrackpad = false {
        didSet {Options.shared.saveOptions()}
    }
    var smoothVertical = true {
        didSet {Options.shared.saveOptions()}
    }
    var smoothHorizontal = true {
        didSet {Options.shared.saveOptions()}
    }
    var durationBeforeSimTrackpadLock: Double? {
        didSet {Options.shared.saveOptions()}
    }
    // 工具
    static func generateDurationTransition(with duration: Double) -> Double {
        // 上界, 此处需要与界面的 Slider 上界保持同步, 并添加 0.2 的偏移令结果不为 0
        let upperLimit = 5.0 + 0.2
        // 生成数据 (https://www.wolframalpha.com/input/?i=1+-+(sqrt+x%2F5)+%3D+y)
        let val = 1-(duration/upperLimit).squareRoot()
        // 三位小数
        return Double(round(1000 * val)/1000)
    }
}
extension OPTIONS_SCROLL_DEFAULT: Equatable {
    static func == (l: OPTIONS_SCROLL_DEFAULT, r: OPTIONS_SCROLL_DEFAULT) -> Bool {
        return (
            l.smooth == r.smooth &&
            l.reverse == r.smooth &&
            l.reverseVertical == r.reverseVertical &&
            l.reverseHorizontal == r.reverseHorizontal &&
            l.dash == r.dash &&
            l.toggle == r.toggle &&
            l.block == r.block &&
            l.step == r.step &&
            l.speed == r.speed &&
            l.duration == r.duration &&
            l.deadZone == r.deadZone &&
            l.smoothSimTrackpad == r.smoothSimTrackpad &&
            l.smoothVertical == r.smoothVertical &&
            l.smoothHorizontal == r.smoothHorizontal &&
            l.durationBeforeSimTrackpadLock == r.durationBeforeSimTrackpadLock
        )
    }
}

// 例外应用
class OPTIONS_APPLICATION_DEFAULT {
    var allowlist = false {
        didSet {Options.shared.saveOptions()}
    }
    var applications = EnhanceArray<Application>(
        matchKey: "path",
        forObserver: {() in Options.shared.saveOptions()}
    )
}
