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

// 修饰键
struct MODIFIER_KEY {
    static let controlLeft = CGKeyCode(59)
    static let controlRight = CGKeyCode(62)
    static let optionLeft = CGKeyCode(58)
    static let optionRight = CGKeyCode(61)
    static let commandLeft = CGKeyCode(55)
    static let commandRight = CGKeyCode(54)
    static let shiftLeft = CGKeyCode(56)
    static let shiftRight = CGKeyCode(60)
}
struct MODIFIER_KEY_SET {
    static let all = ( codes: [MODIFIER_KEY.controlLeft, MODIFIER_KEY.optionLeft, MODIFIER_KEY.commandLeft, MODIFIER_KEY.shiftLeft] , mask: [] )
    static let control = ( codes: [MODIFIER_KEY.controlLeft, MODIFIER_KEY.controlRight], mask: CGEventFlags.maskControl )
    static let option = ( codes: [MODIFIER_KEY.optionLeft, MODIFIER_KEY.optionRight], mask: CGEventFlags.maskAlternate )
    static let command = ( codes: [MODIFIER_KEY.commandLeft, MODIFIER_KEY.commandRight], mask: CGEventFlags.maskCommand )
    static let shift = ( codes: [MODIFIER_KEY.shiftLeft, MODIFIER_KEY.shiftRight], mask: CGEventFlags.maskShift )
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
    static let advanced = "advanced"
    static let advancedWithApplication = "advancedWithApplication"
    static let exception = "exception"
    static let exceptionInput = "exceptionInput"
    static let list = [general, advanced, exception]
}
let PANEL_PADDING = CGFloat(42.0) // 顶部导航栏高度
let TOOLBAR_HEIGHT = CGFloat(38.0) // 偏好的 Toolbar 高度

// 气泡弹窗
struct POPOVER_IDENTIFIER {
    static let statusItemPopoverViewController = "statusItemPopoverViewController"
    static let statusItemMainPanelViewController = "statusItemMainPanelViewController"
}

// 事件处理应用
struct SPECIAL_EVENT_SOURCE_APPLICATION {
    static let logitechOptions = "com.logitech.manager.daemon"
}

// 默认设置项
// 全局参数
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
    // 例外
    var allowlist = false {
        didSet {Options.shared.saveOptions()}
    }
    var applications = EnhanceArray<ExceptionalApplication>(
        matchKey: "path",
        forObserver: {() in Options.shared.saveOptions()}
    )
}
// 滚动参数
class OPTIONS_SCROLL_BASIC_DEFAULT: Codable {
    // 基础
    var smooth = true {
        didSet {Options.shared.saveOptions()}
    }
    var reverse = true {
        didSet {Options.shared.saveOptions()}
    }
}
// 滚动参数
class OPTIONS_SCROLL_ADVANCED_DEFAULT: Codable {
    // 高级
    var dash:Int? = 0 {
        didSet {Options.shared.saveOptions()}
    }
    var toggle:Int? = 0 {
        didSet {Options.shared.saveOptions()}
    }
    var block:Int? = 0 {
        didSet {Options.shared.saveOptions()}
    }
    var step = 35.0 {
        didSet {Options.shared.saveOptions()}
    }
    var speed = 3.00 {
        didSet {Options.shared.saveOptions()}
    }
    var duration = 3.90 {
        willSet {self.durationTransition = OPTIONS_SCROLL_ADVANCED_DEFAULT.generateDurationTransition(with: newValue)}
        didSet {Options.shared.saveOptions()}
    }
    var durationTransition = 0.1340 {
        didSet {}
    }
    var precision = 1.00 {
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
extension OPTIONS_SCROLL_ADVANCED_DEFAULT: Equatable {
    static func == (l: OPTIONS_SCROLL_ADVANCED_DEFAULT, r: OPTIONS_SCROLL_ADVANCED_DEFAULT) -> Bool {
        return (
            l.dash == r.dash &&
            l.toggle == r.toggle &&
            l.block == r.block &&
            l.step == r.step &&
            l.speed == r.speed &&
            l.duration == r.duration &&
            l.durationTransition == r.durationTransition &&
            l.precision == r.precision
        )
    }
}
